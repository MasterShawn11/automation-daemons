#Agent Onboarding

## Where to Start 
- Machine index: 'manifest.jsonl' (JSON Lines; one session per line0
- Human Narrative truth: 'lab-notes/' (After Action Reports / AARs)
Resuable procedures: 'runbooks/' 
Architecture/threat models: 'design/'

## Ground Rules
- Treat only 'status:published' sessions as authoritative.
Draft session may be incomplete or incorrect. 
If conflicts exist, newest published AAR wins. 

## AAR Schema 
Each AAR in 'lab-notes/' includes YAML front matter with: 
- 'id', 'type', 'date', 'tags', 'systems', 'status', and 'related' artifacts.

## Commit Metadata 
AAR commits include trailers: 
'Session: <session_id>
'Type: aar' 
'Tags: a,b,c'
'Status: published'
'Files: <key files>' 
