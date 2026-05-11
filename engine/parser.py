import re
from datetime import datetime

# Regex pour les échecs SSH (Failed password)
# Exemple: May  8 14:02:00 debian sshd[1234]: Failed password for root from 10.0.1.50 port 54321 ssh2
RE_SSH_FAILURE = r"(?P<timestamp>\w{3}\s+\d+\s\d{2}:\d{2}:\d{2})\s+(?P<hostname>\S+)\ssshd\[\d+\]:\sFailed\spassword\sfor\s(?P<user>\S+)\sfrom\s(?P<source_ip>\d+\.\d+\.\d+\.\d+)"

# Regex pour les succès SSH (Accepted password)
# Exemple: May  8 14:05:00 debian sshd[1234]: Accepted password for gael from 10.0.1.50 port 54322 ssh2
RE_SSH_SUCCESS = r"(?P<timestamp>\w{3}\s+\d+\s\d{2}:\d{2}:\d{2})\s+(?P<hostname>\S+)\ssshd\[\d+\]:\sAccepted\spassword\sfor\s(?P<user>\S+)\sfrom\s(?P<source_ip>\d+\.\d+\.\d+\.\d+)"

def parse_line(line):
    """
    Analyse une ligne de log brute et retourne un dictionnaire structuré.
    Retourne None si la ligne ne correspond à aucun pattern connu.
    """
    try:
        # Test d'échec
        match_fail = re.search(RE_SSH_FAILURE, line)
        if match_fail:
            data = match_fail.groupdict()
            data["event_type"] = "ssh_auth_failure"
            return data

        # Test de succès
        match_success = re.search(RE_SSH_SUCCESS, line)
        if match_success:
            data = match_success.groupdict()
            data["event_type"] = "ssh_auth_success"
            return data
            
    except Exception as e:
        # Robustesse : on ne crash pas sur une ligne bizarre
        return None

    return None

if __name__ == "__main__":
    # Petit test rapide
    test_line = "May  8 14:02:00 debian sshd[1234]: Failed password for root from 10.0.1.50 port 54321 ssh2"
    print(f"Test parsing: {parse_line(test_line)}")
