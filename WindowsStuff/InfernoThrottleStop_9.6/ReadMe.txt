ThrottleStop
Version 9.6
2023 May 22

New Features
- added 13th Gen desktop and mobile Rocket Lake support including 13700HX. 
- restored proper scaling on high dpi 4K monitors. 
- increased maximum IccMax for 12th and 13th Gen processors.
- added Undervolt Protection reporting to the FIVR window. 
- fixed FIVR - PL4 reporting for some CPUs.
- disabled the TS Bench - Random MHz feature when TPL - Speed Shift is not checked.
- improved the Windows Defender Boost feature so it begins immediately when ThrottleStop starts.
- added ExitTime=1 INI option to force ThrottleStop to exit 1 second after it starts. 
- disabled safe start feature when Stop Data is being used.
- added an extra digit to the microcode version reporting. 
- fixed SLFM check box showing on screen when the CPU does not support SLFM.
- fixed Limit Reasons reporting for Goldmont and Goldmont Plus processors.
- fixed AVX512 bug.

ThrottleStop Windows 11 Compatibility
-------------------------------------
Windows 11 Virtualization Based Security needs to be disabled so ThrottleStop has direct access to the CPU.
https://beebom.com/how-disable-virtualization-based-security-vbs-windows-11/

Kevin Glynn
throttlestop@shaw.ca
