from json import dumps, loads
import boto3
from os import environ
from urllib.parse import urlunparse
from urllib import request as urllib_request
from ssl import create_default_context
from base64 import b64encode
from traceback import format_exc
from copy import deepcopy

class CustomException(Exception):
    pass

def getToken(api_endpoint, api_id, api_secret):
    """Generate temporary API access token for ExtraHop."""
    auth = b64encode(bytes(api_id + ":" + api_secret, "utf-8")).decode("utf-8")
    url = urlunparse(("https", api_endpoint, "/oauth2/token", "", "", ""))
    data = "grant_type=client_credentials".encode("utf-8")

    ctx = create_default_context()
    req = urllib_request.Request(url, data=data, method='POST')
    req.add_header("Accept", "application/json")
    req.add_header("Authorization", f"Basic {auth}")
    req.add_header('Content-Type', 'application/x-www-form-urlencoded')
    req.add_header('Content-Length', len(data))

    with urllib_request.urlopen(req, context=ctx) as response:
        if response.status == 200:
            return loads(response.read())["access_token"]
        else:
            raise CustomException(f"Token request failed with status: {response.status}")

def addEHids(mac_addresses, mapping, api_endpoint, api_token):
    """Retrieve ExtraHop device IDs and map them to EC2 network interfaces."""
    url = urlunparse(("https", api_endpoint, "/api/v1/devices/search", "", "", ""))
    
    rules = []
    for macaddr in mac_addresses:
        rules.append({"field": "macaddr", "operand": macaddr, "operator": "="})
    
    search = {"filter": {"operator": "or", "rules": rules}}
    data = dumps(search).encode("utf-8")

    ctx = create_default_context()
    req = urllib_request.Request(url, data=data, method='POST')
    req.add_header("Authorization", f"Bearer {api_token}")
    req.add_header('Content-Type', 'application/json; charset=utf-8')
    req.add_header('Content-Length', len(data))
    
    with urllib_request.urlopen(req, context=ctx) as response:
        if response.status != 200:
            raise CustomException(f"Device search failed with status: {response.status}")
        
        json_response = loads(response.read())
    
    # Map MAC addresses to device IDs
    mac_id_map = {}
    for device in json_response:
        macaddr = device["macaddr"].lower()
        if not device["is_l3"]:
            if macaddr in mac_id_map:
                mac_id_map[macaddr].append(device["id"])
            else:
                mac_id_map[macaddr] = [device["id"]]
    
    to_do = []
    not_found = []
    
    for instance in mapping:
        aws_mac = instance["macaddr"]
        if aws_mac in mac_id_map:
            instance["id"] = mac_id_map[aws_mac]
            instance.pop("macaddr")
            to_do.append(instance)
        else:
            not_found.append(aws_mac)
    
    return to_do, not_found

def updateMeta(device, dev_id, api_endpoint, api_token):
    """Add cloud properties to devices in ExtraHop."""
    supported_attributes = [
        "cloud_instance_id", "cloud_instance_type", "cloud_instance_name",
        "cloud_account", "vpc_id", "description"
    ]
    
    # Filter to only supported attributes
    filtered_device = {}
    for attr in supported_attributes:
        if attr in device:
            filtered_device[attr] = device[attr]

    url = urlunparse(("https", api_endpoint, f"/api/v1/devices/{str(dev_id)}", "", "", ""))
    data = dumps(filtered_device).encode("utf-8")

    ctx = create_default_context()
    req = urllib_request.Request(url, data=data, method='PATCH')
    req.add_header("Authorization", f"Bearer {api_token}")
    req.add_header('Content-Type', 'application/json; charset=utf-8')
    req.add_header('Content-Length', len(data))
    
    with urllib_request.urlopen(req, context=ctx) as response:
        return response.status == 204

def update_extrahop_metadata(aws_map, api_endpoint, api_id, api_secret):
    """Update ExtraHop with cloud metadata."""
    api_token = getToken(api_endpoint, api_id, api_secret)
    if not api_token:
        raise CustomException("Failed to obtain API token")
    
    mac_addresses = [x["macaddr"] for x in aws_map]
    aws_map, not_found = addEHids(mac_addresses, aws_map, api_endpoint, api_token)
    
    updates = []
    failed = []
    
    for device in aws_map:
        ids = device.pop("id")
        for device_id in ids:
            if updateMeta(device, device_id, api_endpoint, api_token):
                updates.append(str(device_id))
            else:
                failed.append(str(device_id))
    
    results = {
        "updated_device_ids": updates,
        "update_failed_device_ids": failed,
        "macaddr_not_found_on_eh": not_found,
    }
    
    print(f"Update results: {dumps(results)}")
    
    if failed or not_found:
        raise CustomException("Some devices failed to update or were not found")

def handler(event, context):
    """Process SQS messages with cloud properties updates."""
    print(f"Processing {len(event['Records'])} messages")
    
    # Get environment variables
    ndr_monitoring_api_secret_arn = environ.get("ndr_monitoring_api_secret_arn")
    cloud_properties_queue_url = environ.get("cloud_properties_queue_url")
    region = environ.get("region")

    # Initialize clients
    secretsmanager_client = boto3.client('secretsmanager', region_name=region)
    sqs = boto3.client('sqs', region_name=region)

    # Get API credentials
    secret_response = secretsmanager_client.get_secret_value(
        SecretId=ndr_monitoring_api_secret_arn
    )
    api_secret = loads(secret_response["SecretString"])

    # Process each SQS record
    for record in event["Records"]:
        receipt_handle = record["receiptHandle"]
        
        try:
            aws_map = loads(record["body"])
            print(f"Processing cloud properties for {len(aws_map)} devices")
            
            update_extrahop_metadata(
                aws_map, 
                api_secret["api_endpoint"], 
                api_secret["api_id"], 
                api_secret["api_secret"]
            )
            
            # Delete message on success
            sqs.delete_message(
                QueueUrl=cloud_properties_queue_url,
                ReceiptHandle=receipt_handle
            )
            print("Message processed and deleted")
            
        except Exception as e:
            print(f"Error processing message: {format_exc()}")

if __name__ == "__main__":
    event = loads(environ.get("event", '{}'))
    context = loads(environ.get("context", '{}'))
    handler(event, context)