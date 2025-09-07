#!/usr/bin/env python3
"""
Convert session data to iOS DhikrCounter format.
Supports both CSV and JSON input formats.
"""
import json
import csv
import sys
import os
import subprocess
import shutil
from datetime import datetime
import uuid

def read_csv_session(csv_path):
    """Read CSV session data and extract metadata from comments."""
    metadata = {}
    sensor_data = []
    
    with open(csv_path, 'r') as f:
        lines = f.readlines()
    
    # Extract metadata from comments
    for line in lines:
        if line.startswith('#'):
            if 'Session ID:' in line:
                metadata['sessionId'] = line.split('Session ID:')[1].strip()
            elif 'Start Time:' in line:
                start_time_str = line.split('Start Time:')[1].strip()
                # Convert to timestamp
                dt = datetime.fromisoformat(start_time_str.replace(' +0000', '+00:00'))
                metadata['startTime'] = dt.isoformat()
            elif 'Duration:' in line:
                duration_str = line.split('Duration:')[1].strip().replace('s', '')
                metadata['duration'] = float(duration_str)
            elif 'Total Readings:' in line:
                metadata['totalReadings'] = int(line.split('Total Readings:')[1].strip())
            elif 'update_interval_s=' in line:
                metadata['samplingRate'] = 1.0 / float(line.split('update_interval_s=')[1].strip())
    
    # Read sensor data
    reader = csv.DictReader(filter(lambda row: not row.startswith('#'), lines))
    for row in reader:
        sensor_reading = {
            "timestamp": datetime.fromtimestamp(float(row['epoch_s'])).isoformat() + 'Z',
            "motionTimestamp": float(row['time_s']),
            "epochTimestamp": float(row['epoch_s']),
            "userAcceleration": [
                float(row['userAccelerationX']),
                float(row['userAccelerationY']),
                float(row['userAccelerationZ'])
            ],
            "gravity": [
                float(row['gravityX']),
                float(row['gravityY']),
                float(row['gravityZ'])
            ],
            "rotationRate": [
                float(row['rotationRateX']),
                float(row['rotationRateY']),
                float(row['rotationRateZ'])
            ],
            "attitude": [
                float(row['attitude_qW']),
                float(row['attitude_qX']),
                float(row['attitude_qY']),
                float(row['attitude_qZ'])
            ],
            "activityIndex": 1.0,  # Default value
            "detectionScore": None,
            "sessionState": "activeDhikr"
        }
        sensor_data.append(sensor_reading)
    
    return metadata, sensor_data

def read_json_session(json_path):
    """Read JSON session data."""
    with open(json_path, 'r') as f:
        data = json.load(f)
    
    metadata = data['metadata']
    sensor_data = []
    
    for reading in data['sensorData']:
        # Convert from Watch format to iOS format
        sensor_reading = {
            "timestamp": datetime.fromtimestamp(reading['epoch_s']).isoformat() + 'Z',
            "motionTimestamp": reading['time_s'],
            "epochTimestamp": reading['epoch_s'],
            "userAcceleration": [
                reading['userAcceleration']['x'],
                reading['userAcceleration']['y'], 
                reading['userAcceleration']['z']
            ],
            "gravity": [
                reading.get('gravity', {}).get('x', 0.0),
                reading.get('gravity', {}).get('y', 0.0),
                reading.get('gravity', {}).get('z', 0.0)
            ],
            "rotationRate": [
                reading['rotationRate']['x'],
                reading['rotationRate']['y'],
                reading['rotationRate']['z']
            ],
            "attitude": [
                reading['attitude']['w'],
                reading['attitude']['x'],
                reading['attitude']['y'],
                reading['attitude']['z']
            ],
            "activityIndex": 1.0,
            "detectionScore": None,
            "sessionState": "activeDhikr"
        }
        sensor_data.append(sensor_reading)
    
    return metadata, sensor_data

def find_simulator_documents_path():
    """Find the Documents directory for DhikrCounter app in the running simulator."""
    try:
        # Find running simulators
        result = subprocess.run(['xcrun', 'simctl', 'list', 'devices'], 
                              capture_output=True, text=True, check=True)
        
        # Look for booted simulator
        for line in result.stdout.split('\n'):
            if 'Booted' in line and ('iPhone' in line or 'iPad' in line):
                # Extract device name
                device_name = line.split('(')[0].strip()
                print(f"📱 Found running simulator: {device_name}")
                
                # Get app container path
                container_result = subprocess.run([
                    'xcrun', 'simctl', 'get_app_container', 
                    device_name, 'com.fuutaworks.DhikrCounter', 'data'
                ], capture_output=True, text=True, check=True)
                
                container_path = container_result.stdout.strip()
                documents_path = os.path.join(container_path, 'Documents')
                
                if os.path.exists(documents_path):
                    print(f"📁 App Documents path: {documents_path}")
                    return documents_path
                else:
                    print(f"⚠️  Documents directory doesn't exist yet: {documents_path}")
                    # Create it
                    os.makedirs(documents_path, exist_ok=True)
                    print(f"✅ Created Documents directory: {documents_path}")
                    return documents_path
        
        print("❌ No running simulator found")
        return None
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Error finding simulator: {e}")
        return None

def copy_to_simulator(output_file):
    """Copy the converted session file to the running simulator's Documents directory."""
    simulator_docs = find_simulator_documents_path()
    if not simulator_docs:
        print("⚠️  Could not find simulator Documents directory")
        return False
    
    try:
        # Copy file to simulator
        dest_path = os.path.join(simulator_docs, os.path.basename(output_file))
        shutil.copy2(output_file, dest_path)
        print(f"📲 Copied to simulator: {dest_path}")
        return True
    except Exception as e:
        print(f"❌ Error copying to simulator: {e}")
        return False

def create_ios_session(metadata, sensor_data):
    """Create iOS PersistedSessionData format."""
    session_id = metadata.get('sessionId', str(uuid.uuid4()))
    
    # Parse start time
    if isinstance(metadata.get('startTime'), str):
        start_time = metadata['startTime']
    else:
        # Convert timestamp to ISO string
        start_time = datetime.fromtimestamp(metadata.get('startTime', 0)).isoformat() + 'Z'
    
    # Calculate end time
    duration = metadata.get('duration', 0)
    if isinstance(metadata.get('startTime'), str):
        start_dt = datetime.fromisoformat(metadata['startTime'].replace('Z', '+00:00'))
    else:
        start_dt = datetime.fromtimestamp(metadata.get('startTime', 0))
    
    end_dt = start_dt.timestamp() + duration
    end_time = datetime.fromtimestamp(end_dt).isoformat() + 'Z'
    
    # Create flat PersistedSessionData structure
    return {
        "sessionId": session_id,
        "startTime": start_time,
        "endTime": end_time,
        "sessionDuration": duration,
        "totalPinches": 0,  # Will be updated by analysis
        "detectedPinches": 0,  # Will be updated by analysis  
        "manualCorrections": 0,
        "notes": f"Imported session - {len(sensor_data)} readings",
        "actualPinchCount": None,
        "sensorData": sensor_data,
        "detectionEvents": [],
        "motionInterruptions": None
    }

def main():
    # Parse arguments
    should_copy_to_simulator = False
    args = sys.argv[1:]
    
    if '--copy-to-simulator' in args:
        should_copy_to_simulator = True
        args.remove('--copy-to-simulator')
    
    if len(args) < 1 or len(args) > 2:
        print("Usage: python convert_session_for_ios.py <input_file> [output_file] [--copy-to-simulator]")
        print("  --copy-to-simulator: Automatically copy to running iOS simulator")
        print("  If output_file is omitted, uses session_<ID>.json")
        sys.exit(1)
    
    input_file = args[0]
    output_file = args[1] if len(args) > 1 else None
    
    if not os.path.exists(input_file):
        print(f"Error: Input file {input_file} not found")
        sys.exit(1)
    
    # Determine file type and read data
    if input_file.endswith('.csv'):
        print(f"Reading CSV session data from {input_file}")
        metadata, sensor_data = read_csv_session(input_file)
    elif input_file.endswith('.json'):
        print(f"Reading JSON session data from {input_file}")
        metadata, sensor_data = read_json_session(input_file)
    else:
        print("Error: Input file must be .csv or .json")
        sys.exit(1)
    
    # Create iOS format
    ios_session = create_ios_session(metadata, sensor_data)
    
    # Generate proper filename if not provided or doesn't follow pattern
    session_id = ios_session['sessionId']
    if output_file is None:
        output_file = f"session_{session_id}.json"
        print(f"📝 Using default output filename: {output_file}")
    elif not output_file.startswith('session_') or not output_file.endswith('.json'):
        output_file = f"session_{session_id}.json"
        print(f"⚠️  Adjusting output filename to: {output_file}")
    
    # Write output
    with open(output_file, 'w') as f:
        json.dump(ios_session, f, indent=2)
    
    print(f"✅ Converted session to iOS format:")
    print(f"   Session ID: {ios_session['sessionId']}")
    print(f"   Duration: {ios_session['sessionDuration']}s")
    print(f"   Sensor readings: {len(ios_session['sensorData'])}")
    print(f"   Output file: {output_file}")
    
    # Copy to simulator if requested
    if should_copy_to_simulator:
        print("\n🚀 Copying to iOS simulator...")
        if copy_to_simulator(output_file):
            print("✅ Successfully copied to simulator!")
        else:
            print("❌ Failed to copy to simulator")

if __name__ == "__main__":
    main()