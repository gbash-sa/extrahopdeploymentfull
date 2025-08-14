# lambda/traffic_mirror_manager.py
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    """
    Manages traffic mirroring sessions based on EC2 instance tags
    """
    try:
        # Get configuration from environment
        MIRROR_TAG_KEY = os.environ.get('MIRROR_TAG_KEY', 'TrafficMirror')
        MIRROR_TAG_VALUES = os.environ.get('MIRROR_TAG_VALUES', 'enabled,true').split(',')
        MIRROR_TARGET_ID = os.environ['MIRROR_TARGET_ID']
        MIRROR_FILTER_ID = os.environ['MIRROR_FILTER_ID']
        VPC_ID = os.environ.get('VPC_ID')
        
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        logger.info(f"Config - Tag: {MIRROR_TAG_KEY}, Values: {MIRROR_TAG_VALUES}")
        logger.info(f"Target: {MIRROR_TARGET_ID}, Filter: {MIRROR_FILTER_ID}")
        
        # Find instances that should have traffic mirroring
        filters = [
            {'Name': f'tag:{MIRROR_TAG_KEY}', 'Values': MIRROR_TAG_VALUES},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
        
        if VPC_ID:
            filters.append({'Name': 'vpc-id', 'Values': [VPC_ID]})
        
        response = ec2.describe_instances(Filters=filters)
        
        target_enis = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                # Get primary ENI
                for eni in instance['NetworkInterfaces']:
                    if eni['Attachment']['DeviceIndex'] == 0:
                        target_enis.append({
                            'eni_id': eni['NetworkInterfaceId'],
                            'instance_id': instance['InstanceId']
                        })
                        break
        
        logger.info(f"Found {len(target_enis)} instances that should be mirrored")
        
        # Get existing mirror sessions
        existing_sessions = ec2.describe_traffic_mirror_sessions()
        existing_enis = {
            session['NetworkInterfaceId']: session['TrafficMirrorSessionId'] 
            for session in existing_sessions['TrafficMirrorSessions']
        }
        
        # Create sessions for new targets
        created_count = 0
        for target in target_enis:
            if target['eni_id'] not in existing_enis:
                try:
                    session_number = 1
                    while any(s['SessionNumber'] == session_number and 
                             s['NetworkInterfaceId'] == target['eni_id'] 
                             for s in existing_sessions['TrafficMirrorSessions']):
                        session_number += 1
                    
                    response = ec2.create_traffic_mirror_session(
                        NetworkInterfaceId=target['eni_id'],
                        TrafficMirrorTargetId=MIRROR_TARGET_ID,
                        TrafficMirrorFilterId=MIRROR_FILTER_ID,
                        SessionNumber=session_number,
                        Description=f"Auto-created for {target['instance_id']}",
                        TagSpecifications=[{
                            'ResourceType': 'traffic-mirror-session',
                            'Tags': [
                                {'Key': 'Name', 'Value': f"ExtraHop-{target['instance_id']}"},
                                {'Key': 'ManagedBy', 'Value': 'ExtraHop-Lambda'},
                                {'Key': 'InstanceId', 'Value': target['instance_id']}
                            ]
                        }]
                    )
                    logger.info(f"Created mirror session for ENI {target['eni_id']}")
                    created_count += 1
                except Exception as e:
                    logger.error(f"Failed to create session for {target['eni_id']}: {e}")
        
        # Clean up sessions for instances without the tag
        deleted_count = 0
        target_eni_ids = {t['eni_id'] for t in target_enis}
        
        for eni_id, session_id in existing_enis.items():
            if eni_id not in target_eni_ids:
                try:
                    # Check if ENI/instance still exists and verify tag
                    should_delete = True
                    try:
                        eni_response = ec2.describe_network_interfaces(NetworkInterfaceIds=[eni_id])
                        if eni_response['NetworkInterfaces']:
                            eni = eni_response['NetworkInterfaces'][0]
                            attachment = eni.get('Attachment', {})
                            if 'InstanceId' in attachment:
                                instance_id = attachment['InstanceId']
                                # Check if instance still has the right tag
                                inst_response = ec2.describe_instances(InstanceIds=[instance_id])
                                if inst_response['Reservations']:
                                    instance = inst_response['Reservations'][0]['Instances'][0]
                                    if instance['State']['Name'] == 'running':
                                        tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
                                        if tags.get(MIRROR_TAG_KEY) in MIRROR_TAG_VALUES:
                                            should_delete = False
                    except Exception:
                        pass  # If we can't check, assume it should be deleted
                    
                    if should_delete:
                        ec2.delete_traffic_mirror_session(TrafficMirrorSessionId=session_id)
                        logger.info(f"Deleted mirror session {session_id} for ENI {eni_id}")
                        deleted_count += 1
                        
                except Exception as e:
                    logger.error(f"Failed to delete session {session_id}: {e}")
        
        result = {
            'created_sessions': created_count,
            'deleted_sessions': deleted_count,
            'total_target_instances': len(target_enis)
        }
        
        logger.info(f"Result: {result}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(result)
        }
        
    except Exception as e:
        logger.error(f"Lambda execution failed: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }