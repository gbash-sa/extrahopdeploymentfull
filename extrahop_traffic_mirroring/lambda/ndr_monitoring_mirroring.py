from json import dumps, loads
import boto3
from os import environ
from traceback import format_exc

class CustomException(Exception):
    pass

def describe_instances_in_vpc(ec2_client, vpc_id, instance_state_name_filters=['pending','running','shutting-down','stopping','stopped']):
    """Return all instances within a specific VPC, excluding terminated instances."""
    max_results = 1000
    filters = [
        {
            'Name': 'instance-state-name',
            'Values': instance_state_name_filters
        },
        {
            'Name': 'vpc-id',
            'Values': [vpc_id]
        }
    ]
    
    response = ec2_client.describe_instances(Filters=filters, MaxResults=max_results)
    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            yield instance
    
    while response.get("NextToken"):
        response = ec2_client.describe_instances(
            Filters=filters, 
            MaxResults=max_results, 
            NextToken=response["NextToken"]
        )
        for reservation in response["Reservations"]:
            for instance in reservation["Instances"]:
                yield instance

def describe_traffic_mirror_sessions(ec2_client, filters=[]):
    """Describe traffic mirror sessions with pagination."""
    max_results = 1000
    response = ec2_client.describe_traffic_mirror_sessions(MaxResults=max_results, Filters=filters)
    
    for session in response["TrafficMirrorSessions"]:
        yield session
    
    while response.get("NextToken"):
        response = ec2_client.describe_traffic_mirror_sessions(
            MaxResults=max_results, 
            Filters=filters, 
            NextToken=response["NextToken"]
        )
        for session in response["TrafficMirrorSessions"]:
            yield session

def instance_type_supported(instance):
    """Check if instance type supports traffic mirroring."""
    supported_families = [
        'a1', 'm4', 'm5', 'm5a', 'm5ad', 'm5d', 'm6g', 'm6gd', 
        't3', 't3a', 't4g', 'c4', 'c5', 'c5a', 'c5ad', 'c5d', 
        'c5n', 'c6g', 'c6gd', 'd2', 'h1', 'i3', 'i3en', 'g3', 
        'g3s', 'g5g', 'p2', 'p3', 'p3dn.24xlarge', 'r4', 'r5', 
        'r5a', 'r5ad', 'r5b', 'r5d', 'r6g', 'r6gd', 'x1', 'x1e', 
        'x2gd', 'z1d'
    ]
    
    instance_type = instance["InstanceType"]
    instance_family = instance_type.split(".")[0]
    
    return instance_family in supported_families or instance_type in supported_families

def create_traffic_mirror_session(ec2_client, traffic_mirror_target_id, traffic_mirror_filter_id, item, session_number=1):
    """Create a traffic mirror session."""
    try:
        response = ec2_client.create_traffic_mirror_session(
            NetworkInterfaceId=item["networkInterfaceId"],
            TrafficMirrorTargetId=traffic_mirror_target_id,
            TrafficMirrorFilterId=traffic_mirror_filter_id,
            SessionNumber=session_number,
            TagSpecifications=[
                {
                    'ResourceType': 'traffic-mirror-session',
                    'Tags': item["tags"]
                }
            ]
        )
        
        session = response["TrafficMirrorSession"]
        result = {
            "TrafficMirrorSessionId": session["TrafficMirrorSessionId"],
            "NetworkInterfaceId": session["NetworkInterfaceId"]
        }
        
        print(f"Traffic mirror session created: {dumps(result)}")
        return True
        
    except Exception as e:
        error_msg = str(e)
        if "NetworkInterfaceNotSupported" in error_msg:
            print(f"Instance type not supported for traffic mirroring")
        elif "already exists" in error_msg.lower():
            print(f"Traffic mirror session already exists")
            return True
        else:
            print(f"Error creating traffic mirror session: {error_msg}")
        
        return False

def delete_traffic_mirror_session(ec2_client, session):
    """Delete a traffic mirror session."""
    try:
        session_id = session["TrafficMirrorSessionId"]
        ec2_client.delete_traffic_mirror_session(TrafficMirrorSessionId=session_id)
        print(f"Traffic mirror session deleted: {session_id}")
        return True
        
    except Exception as e:
        if "InvalidTrafficMirrorSessionId.NotFound" in str(e):
            return True
        print(f"Error deleting traffic mirror session: {str(e)}")
        return False

def handler(event, context):
    """Main Lambda handler function."""
    print(f"Lambda invoked with event: {dumps(event)}")
    
    # Get environment variables
    traffic_mirror_target_id = environ.get("traffic_mirror_target_id")
    traffic_mirror_filter_id = environ.get("traffic_mirror_filter_id")
    vpc_id = environ.get("vpc_id")
    region = environ.get("region")
    cloud_properties_queue_url = environ.get("cloud_properties_queue_url")
    
    # Get GSO tags from environment
    gso_tags = {key[4:]: value for key, value in environ.items() if key.startswith("tag_")}
    
    print(f"Configuration: vpc_id={vpc_id}, region={region}")
    print(f"Target ID: {traffic_mirror_target_id}")
    print(f"Filter ID: {traffic_mirror_filter_id}")
    
    # Initialize AWS clients
    ec2_client = boto3.client('ec2', region_name=region)
    sqs_client = boto3.client('sqs', region_name=region)
    
    # Create filters for existing traffic mirror sessions
    session_filters = [
        {'Name': 'session-number', 'Values': ['1']},
        {'Name': 'traffic-mirror-filter-id', 'Values': [traffic_mirror_filter_id]},
        {'Name': 'traffic-mirror-target-id', 'Values': [traffic_mirror_target_id]}
    ]
    
    # Get existing sessions
    existing_sessions = {}
    for session in describe_traffic_mirror_sessions(ec2_client, session_filters):
        existing_sessions[session["NetworkInterfaceId"]] = session
    
    print(f"Found {len(existing_sessions)} existing mirror sessions")
    
    # Process instances that need session deletion (stopped/terminated)
    deleted_count = 0
    for instance in describe_instances_in_vpc(
        ec2_client, vpc_id, 
        instance_state_name_filters=['shutting-down', 'terminated', 'stopping', 'stopped']
    ):
        for network_interface in instance["NetworkInterfaces"]:
            eni_id = network_interface["NetworkInterfaceId"]
            if eni_id in existing_sessions:
                if delete_traffic_mirror_session(ec2_client, existing_sessions[eni_id]):
                    deleted_count += 1
    
    # Process instances that need sessions (running/pending)
    created_count = 0
    processed_count = 0
    for instance in describe_instances_in_vpc(
        ec2_client, vpc_id, 
        instance_state_name_filters=['pending', 'running']
    ):
        processed_count += 1
        
        if not instance_type_supported(instance):
            print(f"Instance {instance['InstanceId']} type {instance['InstanceType']} not supported")
            continue
        
        # Prepare session tags
        session_tags = []
        instance_tags = instance.get("Tags", [])
        
        # Add non-reserved instance tags
        for tag in instance_tags:
            if not tag['Key'].startswith('aws:') and tag['Key'] not in ['instanceId']:
                session_tags.append(tag)
        
        # Add required tags
        session_tags.append({"Key": "instanceId", "Value": instance["InstanceId"]})
        
        # Add GSO tags
        for key, value in gso_tags.items():
            session_tags.append({"Key": key, "Value": value})
        
        # Create sessions for network interfaces that don't have them
        for network_interface in instance["NetworkInterfaces"]:
            eni_id = network_interface["NetworkInterfaceId"]
            
            if eni_id not in existing_sessions:
                item = {
                    "networkInterfaceId": eni_id,
                    "tags": session_tags
                }
                
                if create_traffic_mirror_session(
                    ec2_client, traffic_mirror_target_id, traffic_mirror_filter_id, item
                ):
                    created_count += 1
                    
                    # Send cloud properties to SQS
                    instance_name = ""
                    for tag in instance_tags:
                        if tag['Key'] == 'Name':
                            instance_name = tag['Value']
                            break
                    
                    aws_map = [{
                        "macaddr": network_interface["MacAddress"],
                        "cloud_instance_id": instance["InstanceId"],
                        "cloud_instance_type": instance["InstanceType"],
                        "cloud_instance_name": instance_name,
                        "cloud_account": network_interface["OwnerId"],
                        "vpc_id": network_interface["VpcId"],
                        "description": region,
                        "networkInterfaceId": network_interface["NetworkInterfaceId"]
                    }]
                    
                    if cloud_properties_queue_url:
                        sqs_client.send_message(
                            QueueUrl=cloud_properties_queue_url, 
                            MessageBody=dumps(aws_map)
                        )
    
    print(f"Summary: Processed {processed_count} instances, created {created_count} sessions, deleted {deleted_count} sessions")
    
    return {
        'statusCode': 200,
        'body': dumps({
            'processed_instances': processed_count,
            'sessions_created': created_count,
            'sessions_deleted': deleted_count
        })
    }

if __name__ == "__main__":
    event = loads(environ.get("event", '{}'))
    context = loads(environ.get("context", '{}'))
    handler(event, context)