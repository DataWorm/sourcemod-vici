# Sourcemod Plugin: VICI

This plugin for sourcemod sends several server events in json format to a backend server. It is used to collect some statistics and to integrate chatbot functionalities. 

Additional extensions/includes required to run/compile this script are added in this repo. If you want to run this plugin and you received an auth token from the owner, you need to:
*  Add .smx file and extensions to your server running sourcemod in the corresponding directories (restart might be required if extensions were not available before)
*  Create or edit the config file vici.cfg (should be located in ```cstrike/cfg/sourcemod/``` or similar, and insert/change the line ```vici_token "<TOKEN>"``` where ```<TOKEN>``` needs to be replaced with the token assigned for your server
