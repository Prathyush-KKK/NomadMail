$ErrorActionPreference = "Stop"

# Runtime paths. Keep these outside git or under ignored folders.
$env:NOMADINBOX_DATA_DIR = (Join-Path $PSScriptRoot "..\data")
$env:NOMADINBOX_DEFAULT_PROVIDER = "gmail-api"
$env:NOMADINBOX_DEFAULT_FOLDER = "Inbox"
$env:NOMADINBOX_DEFAULT_LIMIT = "25"

# Gmail API OAuth Desktop client JSON.
# Example: C:\Users\you\client_secret_xxx.apps.googleusercontent.com.json
$env:NOMADINBOX_GMAIL_CLIENT_SECRET_JSON = ""
$env:NOMADINBOX_GMAIL_ACCESS_TOKEN = ""
$env:NOMADINBOX_GMAIL_SCOPES = "https://www.googleapis.com/auth/gmail.readonly"
$env:NOMADINBOX_GMAIL_REDIRECT_PORT = "53682"

# Outlook Graph / Microsoft 365.
$env:NOMADINBOX_GRAPH_CLIENT_ID = ""
$env:NOMADINBOX_GRAPH_ACCESS_TOKEN = ""
$env:NOMADINBOX_GRAPH_TENANT = "common"
$env:NOMADINBOX_GRAPH_SCOPES = "offline_access User.Read Mail.Read Mail.ReadWrite Mail.Send"

# Outlook Desktop uses the signed-in Windows Outlook profile.
$env:NOMADINBOX_OUTLOOK_DESKTOP_PROFILE = "default"
