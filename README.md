# RemotelyCheckDefaultBrowser

**Remotely determines the Default Browser for the logged on accounts on a bunch of Windows PCs.**


**SYNOPSIS**

  Ensures Remote Registry, enumerates interactive sessions and loaded profiles (excluding “_Classes” hives),
  then queries per-user and machine-wide default browser settings.


**DESCRIPTION**

  For each computer:
  
    1. Ensures Remote Registry is set to Automatic and started.
    
    2. Uses `quser /server:` to list actual console/RDP sessions.
    
    3. Uses `reg.exe` to list loaded HKU hives (SIDs), excluding any hive ending in “_Classes”.
    
    4. Translates each SID to DOMAIN\User for reporting.
    
    5. Queries each user’s HTTP UserChoice\ProgId via `reg.exe`.
    
    6. If no per-user setting, queries machine default under 
    
       HKLM\SOFTWARE\Clients\StartMenuInternet via `reg.exe`.


