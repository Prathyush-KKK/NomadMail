$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot "src\NomadInbox\NomadInbox.psm1"
$cli = Join-Path $repoRoot "scripts\nomad-inbox.ps1"
$previousDataDir = $env:NOMADINBOX_DATA_DIR
$tempBase = if ([string]::IsNullOrWhiteSpace($env:TEMP)) { Join-Path $env:USERPROFILE "AppData\Local\Temp" } else { $env:TEMP }
$testRoot = Join-Path $tempBase ("nomadinbox-storage-policy-" + [guid]::NewGuid().ToString("n"))

function Assert-StoragePolicy {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function ConvertTo-Base64Url {
    param([string]$Text)
    return [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    $env:NOMADINBOX_DATA_DIR = Join-Path $testRoot "data"

    $module = Import-Module $modulePath -Force -PassThru
    $plainData = ConvertTo-Base64Url "Plain body"
    $htmlData = ConvertTo-Base64Url "<p>HTML body</p>"

    $gmailMessage = [pscustomobject]@{
        id = "gmail-message-1"
        threadId = "gmail-thread-1"
        payload = [pscustomobject]@{
            mimeType = "multipart/mixed"
            body = [pscustomobject]@{ size = 0 }
            parts = @(
                [pscustomobject]@{
                    mimeType = "multipart/alternative"
                    body = [pscustomobject]@{ size = 0 }
                    parts = @(
                        [pscustomobject]@{
                            partId = "1"
                            mimeType = "text/plain"
                            filename = ""
                            body = [pscustomobject]@{ size = 10; data = $plainData }
                        },
                        [pscustomobject]@{
                            partId = "2"
                            mimeType = "text/html"
                            filename = ""
                            body = [pscustomobject]@{ size = 16; data = $htmlData }
                        }
                    )
                },
                [pscustomobject]@{
                    partId = "3"
                    mimeType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                    filename = "sample.xlsx"
                    body = [pscustomobject]@{ size = 1234; attachmentId = "attach-1" }
                }
            )
        }
    }

    $gmailResult = & $module {
        param($Message)
        $body = Get-NomadInboxGmailBodyContent -Payload $Message.payload
        $attachments = @(Get-NomadInboxGmailAttachmentMetadata -Payload $Message.payload)
        $rawCopy = Copy-NomadInboxJsonObject -InputObject $Message
        Remove-NomadInboxGmailInlineBodyData -Node $rawCopy
        [pscustomobject]@{
            body = $body
            attachmentCount = $attachments.Count
            firstAttachmentName = if ($attachments.Count -gt 0) { $attachments[0].name } else { $null }
            sanitizedRawJson = $rawCopy | ConvertTo-Json -Depth 50 -Compress
        }
    } $gmailMessage

    Assert-StoragePolicy ($gmailResult.body.bodyText -eq "Plain body") "Gmail text body was not decoded when includeBodies-style extraction is requested."
    Assert-StoragePolicy ($gmailResult.body.bodyHtml -eq "<p>HTML body</p>") "Gmail HTML body was not decoded when includeBodies-style extraction is requested."
    Assert-StoragePolicy ($gmailResult.attachmentCount -eq 1 -and $gmailResult.firstAttachmentName -eq "sample.xlsx") "Nested Gmail attachment metadata was not discovered."
    Assert-StoragePolicy ($gmailResult.sanitizedRawJson -notlike "*$plainData*" -and $gmailResult.sanitizedRawJson -notlike "*$htmlData*") "Sanitized Gmail raw snapshot still contains inline body data."
    Assert-StoragePolicy ($gmailResult.sanitizedRawJson -like "*dataOmittedByNomadInbox*") "Sanitized Gmail raw snapshot does not mark omitted body data."

    $emlPath = Join-Path $testRoot "duplicate-import.eml"
    @"
From: Storage Test <storage@example.com>
To: Example User <user@example.com>
Subject: Duplicate archive import test
Date: Wed, 13 May 2026 09:15:00 +0530
Message-ID: <duplicate-archive-import@example.com>

This validates archive import upsert behavior.
"@ | Set-Content -LiteralPath $emlPath -Encoding UTF8

    $firstImport = & $cli import eml --path $emlPath --source storage-policy-test --max-messages 1 | ConvertFrom-Json
    $secondImport = & $cli import eml --path $emlPath --source storage-policy-test --max-messages 1 | ConvertFrom-Json
    Assert-StoragePolicy ($firstImport.status -eq "ok" -and $secondImport.status -eq "ok") "Archive import did not complete."

    $archiveMessagesPath = Join-Path $env:NOMADINBOX_DATA_DIR "archive-messages.jsonl"
    $archiveIndexPath = Join-Path $env:NOMADINBOX_DATA_DIR "archive-index.jsonl"
    $archiveMessages = @([System.IO.File]::ReadAllLines($archiveMessagesPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $archiveIndex = @([System.IO.File]::ReadAllLines($archiveIndexPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-StoragePolicy ($archiveMessages.Count -eq 1) "Repeated archive import produced duplicate archive message rows."
    Assert-StoragePolicy ($archiveIndex.Count -eq 1) "Repeated archive import produced duplicate archive index rows."

    [pscustomobject]@{
        status = "ok"
        service = "NomadInbox"
        purpose = "Message storage policy validation"
        gmail = [pscustomobject]@{
            bodyExtraction = "ok"
            rawBodyOmission = "ok"
            attachmentMetadata = "ok"
        }
        archiveImport = [pscustomobject]@{
            upsertedMessages = $archiveMessages.Count
            upsertedIndexRows = $archiveIndex.Count
        }
    } | ConvertTo-Json -Depth 6
} finally {
    if ($null -eq $previousDataDir) {
        Remove-Item Env:\NOMADINBOX_DATA_DIR -ErrorAction SilentlyContinue
    } else {
        $env:NOMADINBOX_DATA_DIR = $previousDataDir
    }
    try {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction Stop
    } catch {
    }
}
