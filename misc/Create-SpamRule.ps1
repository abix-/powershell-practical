[cmdletbinding()]
Param (
    $type,
    $content,
    $score,
    $index,
    $seperator = "space",
    $indexFile = "Create-SpamRule-Index.txt",
    $scriptPath = (Get-Location).Path
)

function drawMenu() {
    $index = getIndex
    Clear-Host
    Write-Host "Rule Index:      $index"
    Write-Host "Rule Seperator:  $seperator"
    Write-Host "1. Subject"
    Write-Host "2. Body"
    Write-Host "3. URL"
    Write-Host ""
    Write-Host "1-3, index, seperator, exit"
    $option = Read-Host 
    $lastoption = $option 
    switch($option) {
        "1" { $type = "Subject"; getContent }
        "2" { $type = "Body"; getContent }
        "3" { $type = "URL"; getContent }
        "index" { 
            Clear-Host
            Write-Host "Current Rule Index: $index"
            $index = Read-Host "New Rule Index"
            $index | Out-File "$scriptPath\$indexFile" -Force
            drawMenu
        }
        "seperator" {
            if($seperator -eq "space") { $seperator = "wildcard"; drawMenu } 
            elseif($seperator -eq "wildcard") { $seperator = "space"; drawMenu }
        }
        "exit" { Exit }
        default { drawMenu }
    }
}


function getContent() {
    Clear-Host
    Write-Host "Rule Index:      $index"
    Write-Host "Rule Seperator:  $seperator"
    Write-Host "Rule Type:       $type"
    $content = Read-Host "Content"
    $score = Read-Host "Score"
    createSpamRule
}


function createSpamRule() {
    $regexContent = "/"
    $words = $content -split " "
    for($i = 0;$i -lt $words.count; $i++) {
        $_w = $words[$i] -replace "/","\/"
        $_w = $_w -replace "'","\'"
        $_w = $_w -replace ".","\."
        if($type -ne "URL") {
            $first = $_w.substring(0,1)
            $regexContent += "[$($first.ToUpper())$($first.ToLower())]$($_w.Substring(1))"
        } else { $regexContent += $_w }
        if($words[$i+1]) {
            if($seperator -eq "space") { $regexContent += " " } 
            elseif($seperator -eq "wildcard") { $regexContent += ".*" }
        } 
    }
    $regexContent += "/"

    switch($type) {
        "Subject" { $ruleTemplate = "header MISC_SPAM$index Subject =~ $regexContent" }
        "Body" { $ruleTemplate = "body MISC_SPAM$index $regexContent" }
        "URL" { $ruleTemplate = "uri MISC_SPAM$index $regexContent" }
    }

    $scoreTemplate = "score MISC_SPAM$index $score"
    $newRule = $ruleTemplate + "`r`n" + $scoreTemplate
    Write-Host ""
    Write-Host $newRule
    $newRule | clip.exe
    Write-Host "This rule has been copied to the clipboard"
    $index++
    $index | Out-File "$scriptPath\$indexFile" -Force
    Read-Host
    drawMenu
}

function getIndex() {
    try { $var = [int](Get-Content $scriptPath\$indexFile -ErrorAction Stop) }
    catch { Write-Host "$scriptPath\$indexFile - Not found. Starting with Rule Index 0"; $var = 0 }
    return $var
}

$index = getIndex
if($type -and $content -and $score) {
    Write-Host "Creating $($type.ToUpper()) Rule for '$content' with a score of $score"
    createSpamRule
} else {
    drawMenu
}