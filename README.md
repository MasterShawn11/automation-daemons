# automations-daemons
Hands-on lab repository focused on automations workflows, long-running processes (daemons), and service management (systemd), documented as chronological After Action Reports (AARs). 
## Repo Map 
- 'lab-notes/' - chronological AARs (session narratives + troubleshooting)
- 'runbooks/; - resusable "how-to" procedures
- 'runbooks/' - resusable "how-to" procedures
- 'design/' - architecture notes and threat models
- 'tools/' - helper scripts (session closeout, validation)
- 'manifest.jsonl' - machine-ingestible session index (one JSON object per line)
- 'INDEX.md' - human-friendly index of latest sessions

## Publishing Workflow 
1) Work session happens (notes/logs captured locally) 
2) Run 'tools/session-closeout.sh' 
3) Review + approve in terminal
4) Script marks AAR as published, commits with structured metadata, and (optionally) pushes
