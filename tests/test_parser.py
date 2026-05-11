import pytest
from engine.parser import parse_line

def test_parse_ssh_failure():
    line = "May  8 14:02:00 debian sshd[1234]: Failed password for root from 10.0.1.50 port 54321 ssh2"
    result = parse_line(line)
    assert result is not None
    assert result["event_type"] == "ssh_auth_failure"
    assert result["user"] == "root"
    assert result["source_ip"] == "10.0.1.50"
    assert result["hostname"] == "debian"

def test_parse_ssh_success():
    line = "May  8 14:05:00 debian sshd[1234]: Accepted password for gael from 10.0.1.50 port 54322 ssh2"
    result = parse_line(line)
    assert result is not None
    assert result["event_type"] == "ssh_auth_success"
    assert result["user"] == "gael"
    assert result["source_ip"] == "10.0.1.50"

def test_parse_invalid_line():
    line = "This is not a log line at all."
    result = parse_line(line)
    assert result is None

def test_parse_malformed_ssh():
    line = "May  8 14:02:00 debian sshd[1234]: Failed password for from port"
    result = parse_line(line)
    assert result is None
