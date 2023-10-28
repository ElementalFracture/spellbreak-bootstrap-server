import time
import os
import subprocess
from socket import AF_INET, SOCK_DGRAM
import threading
import re
import configparser
import psutil

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))

# Config File
config = configparser.ConfigParser()
configRead = config.read(f"{SCRIPT_DIR}/config.ini")
if not configRead:
    raise ValueError("Failed to read the config file!")

# Game Server Configs
gamePathDir = config.get('GameSettings', 'GamePathDirectory')
gameMode = config.get('GameSettings', 'GameMode')
serverLogDir = config.get('GameSettings', 'logdirectory')

# State Machine Configs
IDLE_DURATION = int(config.get('ServerSettings', 'idleTimer'))
SHUTDOWN_WARNING_DURATION = int(config.get('ServerSettings', 'warningtimer'))
CHECK_INTERVAL = int(config.get('ServerSettings','checkInterval'))

# States
RUNNING = "RUNNING"
REFRESH = "REFRESH"
MATCH_COMPLETE = "SHUTDOWN_MATCH_COMPLETE"
SHUTDOWN = "SHUTDOWN"

# Initial state and variables
state = RUNNING
game_server_process = None
game_server_pid = None  # Add this global variable to keep track of the actual game server's PID
last_processed_line = 0
current_log_file = None
last_packet_time = time.time()
last_log_time = time.time()  # Added this to track the last log timestamp

print(f"Game mode set to: {gameMode}")

def get_all_child_pids(parent_pid):
    """Get all child PIDs of a parent process."""
    try:
        parent = psutil.Process(parent_pid)
        return [child.pid for child in parent.children(recursive=True)]
    except psutil.NoSuchProcess:
        print(f"Process with PID {parent_pid} doesn't exist.")
        return []

connected_players = {}
player_index_list = []  # This list should be defined outside of any function

def get_most_recent_log(log_directory):
    log_files = [f for f in os.listdir(log_directory) if f.startswith('g3-') and f.endswith('.log')]
    return sorted(log_files, key=lambda x: os.path.getctime(os.path.join(log_directory, x)))[-1] if log_files else None

def monitor_logs():
    global last_file_position, current_log_file, last_log_time, connected_players, state, game_server_pid

    # Get the most recent log file based on its creation date
    most_recent_log = get_most_recent_log(serverLogDir)
    if not most_recent_log:
        print("No log files found.")
        return

    # If current_log_file is None or a newer log is detected, then proceed with monitoring
    if current_log_file is None or most_recent_log != current_log_file:
        print(f"Monitoring the most recent log file: {most_recent_log}")
        current_log_file = most_recent_log
        last_file_position = 0

    # Ensure ProcessLogs directory exists
    py_log_directory = os.path.join(serverLogDir,"ProcessLogs")
    os.makedirs(py_log_directory, exist_ok=True)
    py_log = os.path.join(py_log_directory, current_log_file.replace('.log', '-process.log'))

    with open(os.path.join(serverLogDir, current_log_file), 'r') as f:
        f.seek(last_file_position)

        lines = f.readlines()
        for line in lines:
            last_log_time = time.time()

            timestamp = re.search(r'\[(.*?)\]', line).group(1) if re.search(r'\[(.*?)\]', line) else None

            # Game engine initialization pattern
            server_start_match = re.search(r'LogInit:Display: Game Engine Initialized\.', line)
            if server_start_match and game_server_pid:
                print(f"[{timestamp}] - {gameMode} Game Server Initialized! PID: {game_server_pid}")
                with open(py_log, 'a') as pl:
                    pl.write(f"[{timestamp}] - {gameMode} Game Server Initialized! PID: {game_server_pid}\n")

            server_end_match = re.search(r'R:GameServer: The match was complete', line)
            if server_end_match:
                print(f"[{timestamp}] - {gameMode} Match completed!")
                with open(py_log, 'a') as pl:
                    pl.write(f"[{timestamp}] - {gameMode} Match completed!  PID: {game_server_pid}\n")
                state = MATCH_COMPLETE

            # Player connection pattern
            connect_match = re.search(r'"Id":"(.*?)".*?"DisplayName":"(.*?)"', line)
            if connect_match:
                player_id = connect_match.group(1)
                display_name = connect_match.group(2)
                
                if display_name not in connected_players:
                    connected_players[display_name] = player_id
                    print(f"[{timestamp}] - {display_name} (ID: {player_id}) connected!")
                    with open(py_log, 'a') as pl:
                        pl.write(f"[{timestamp}] - {display_name} (ID: {player_id}) connected!\n")

            # Player disconnection pattern
            disconnect_match = re.search(r'AGSquadState\.hx:400: Removing player (\w+) from squad', line)
            if disconnect_match:
                display_name = disconnect_match.group(1)
                
                if display_name in connected_players:
                    player_id = connected_players.pop(display_name)  # retrieve and remove from the dictionary
                    print(f"[{timestamp}] - {display_name} (ID: {player_id}) disconnected!")
                    with open(py_log, 'a') as pl:
                        pl.write(f"[{timestamp}] - {display_name} (ID: {player_id}) disconnected!\n")

        last_file_position = f.tell()

def continuous_log_monitoring():
    time.sleep(3)
    while True:
        monitor_logs()
        time.sleep(0.5)

log_thread = threading.Thread(target=continuous_log_monitoring)
log_thread.start()

def start_game_server():
    global game_server_process, game_server_pid
    
    if game_server_process:  # Check if there's already an active game_server_process
        return game_server_pid  # Return game_server_pid if already set

    os.chdir(gamePathDir)
    try:
        print(f"Launching {gameMode} game server...")
        with open(os.devnull, 'w') as devnull:
            game_server_process = subprocess.Popen([f'{gamePathDir}/Start a {gameMode} server.bat'], stdout=devnull, stderr=devnull, shell=True)
        
        # Wait for a brief moment to ensure child processes are spawned
        time.sleep(2)

        # Using psutil to get the child process PID of the actual game server
        children = psutil.Process(game_server_process.pid).children()
        if children:
            game_server_pid = children[0].pid
        else:
            print("Failed to get the child process PID for the game server.")
            return None

        return game_server_pid

    except Exception as e:
        print(f"Failed to start the game server: {e}")
        return None

while True:
    try:
        if state == RUNNING:
            current_time = time.time()
            if game_server_process is None:  # Only if the server isn't already running
                start_game_server()
                monitor_logs()  # Monitor the logs after starting the server
                
            if current_time - last_log_time > (30 * 60):
                state = REFRESH
                print("Warning: Server inactivity. Game server will transition to SHUTDOWN soon if no new activity is detected.")

        elif state == MATCH_COMPLETE:
            time.sleep(3)
            last_processed_line = 0  # Reset the last processed line
            os.system('taskkill /F /T /PID {}'.format(game_server_pid))
            print("Server has been shut down due to match completion.")
            game_server_process = None
            time.sleep(20)
            state = RUNNING

        elif state == REFRESH:
            current_time = time.time()
            if current_time - last_log_time <= (30 * 60):
                # When transitioning from REFRESH to RUNNING, force a restart
                if game_server_process:
                    os.system('taskkill /F /T /PID {}'.format(game_server_pid))
                    game_server_process = None
                    last_processed_line = 0  # Reset the last processed line
                state = RUNNING
                print("Received activity. Resuming game server...")
            elif current_time - last_log_time > (IDLE_DURATION + SHUTDOWN_WARNING_DURATION):
                state = SHUTDOWN

        elif state == SHUTDOWN:
            print("Shutting down game server due to prolonged inactivity...")
            os.system('taskkill /F /PID {}'.format(game_server_pid))
            game_server_process = None
            last_processed_line = 0  # Reset the last processed line
            state = RUNNING
            print(f"Starting {gameMode} server...")

    except Exception as e:
        print(f"Error: {e}")
        time.sleep(10)