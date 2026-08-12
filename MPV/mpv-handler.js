var shell = new ActiveXObject("WScript.Shell");
var fso = new ActiveXObject("Scripting.FileSystemObject");

if (WScript.Arguments.Count() > 0) {
    var rawUrl = WScript.Arguments(0);
    var url = decodeURIComponent(rawUrl.replace(/^mpv:\/\//, ""));
    
    var scriptDir = fso.GetParentFolderName(WScript.ScriptFullName);
    var mpvPath = scriptDir + "\\mpv.exe";
    var pipePath = "\\\\.\\pipe\\mpv-pipe";

    // Attempt to send to an existing MPV instance first (Single-Instance mode)
    // This is nearly instantaneous compared to launching a new process.
    var safeUrl = url.replace(/"/g, '%22');
    var env = shell.Environment("PROCESS");
    env("MPV_URL") = safeUrl;

    try {
        // cmd /v:on /c allows delayed expansion (!MPV_URL!) to prevent command injection
        // from unescaped shell metacharacters in the URL.
        var res = shell.Run('cmd /v:on /c "echo loadfile "!MPV_URL!" > ' + pipePath + '"', 0, true);
        if (res === 0) {
            WScript.Quit();
        }
    } catch (e) {
        // Fallback to new instance
    }

    if (fso.FileExists(mpvPath)) {
        // Launch MPV directly for maximum speed. 
        // 1 = Normal window, false = don't wait for exit.
        shell.Run('"' + mpvPath + '" "' + safeUrl + '"', 1, false);
    }
}
