# mod_offline_post
Send a push notification to a webservice when there's a message being sent to offline users. Supports groupchat and chat.

ejabberd
Tested with ejabberd 18.12

Usage
Add in ejabberd.yaml

modules:

     mod_offline_post:
  
     post_url: "http://..."
    
     auth_token: "AUTHENTICATION_TOKEN"
Credits