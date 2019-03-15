%%%-------------------------------------------------------------------
%%% @author jitendradixit
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 15. Mar 2019 10:43 AM
%%%-------------------------------------------------------------------
-module(mod_offline_post).
-author("jitendradixit").
-export([start/2, stop/1, store_packet/1, get_users_and_subscribers/1, group_chat_push/6, muc_filter_message/3]).

-include("ejabberd.hrl").
-include("xmpp.hrl").
-include("mod_muc_room.hrl").



start(_Host, _Opt) ->
  inets:start(),
  ejabberd_hooks:add(offline_message_hook, _Host, ?MODULE, store_packet, 50),
  ejabberd_hooks:add(muc_filter_message, _Host, ?MODULE, muc_filter_message, 50).

stop(_Host) ->
  ejabberd_hooks:delete(muc_filter_message, _Host, ?MODULE, muc_filter_message, 50),
  ejabberd_hooks:delete(offline_message_hook, _Host, ?MODULE, store_packet, 50).



store_packet({_, #message{from = From, to = To} = Packet} = Acc) ->
  Type = Packet#message.type,
  [{text, _, Body}] = Packet#message.body,
  if
    (Type == chat) and (Body /= <<"">>) ->
      post_offline_message(From, To, Body, Packet#message.id),
      Packet;
    true ->
      Packet
  end,
  Acc.

get_users_and_subscribers(StateData) ->
  OnlineSubscribers = maps:fold(
    fun(LJID, _, Acc) ->
      LBareJID = jid:remove_resource(LJID),
      case is_subscriber(LBareJID, StateData) of
        true ->
          ?SETS:add_element(LBareJID, Acc);
        false ->
          Acc
      end
    end, ?SETS:new(), StateData#state.users),
  maps:fold(
    fun(LBareJID, #subscriber{nick = Nick}, Acc) ->
      case ?SETS:is_element(LBareJID, OnlineSubscribers) of
        false ->
          maps:put(LBareJID,
            #user{jid = jid:make(LBareJID),
              nick = Nick,
              role = none,
              last_presence = undefined},
            Acc);
        true ->
          Acc
      end
    end, StateData#state.users, StateData#state.subscribers).

group_chat_push(From, To, Packet, GroupId, State, Body) ->
  LTo = jid:tolower(To),
  IsOffline = case maps:get(LTo, State#state.users, error) of
                #user{last_presence = undefined} -> true;
                error -> true;
                _ -> false
              end,
  if IsOffline ->
    ToUser = binary_to_list(To#jid.luser),
    FromUser = binary_to_list(From#jid.luser),
    FinalBody = binary_to_list(Body),
    TypeChat = "groupchat",
    MessageId = binary_to_list(Packet#message.id),
    PostUrl = gen_mod:get_module_opt(To#jid.lserver, ?MODULE, post_url, fun(S) ->
      iolist_to_binary(S) end, list_to_binary("")),
    DataBody = "{\"toJID\":\"" ++ ToUser ++ "\",\"fromJID\":\"" ++ FromUser ++ "\",\"body\":\"" ++ FinalBody ++ "\",\"messageID\":\"" ++ MessageId ++ "\",\"type\":\"" ++ TypeChat ++ "\",\"groupId\":\"" ++ GroupId ++ "\"}",
    Method = post,
    URL = binary_to_list(PostUrl),
    Header = [],
    Type = "application/json",
    HTTPOptions = [],
    Options = [],
    inets:start(),
    ssl:start(),
    httpc:request(Method, {URL, Header, Type, DataBody}, HTTPOptions, Options);
    true ->
      false
  end.

muc_filter_message(#message{from = From} = Packet,
    #state{config = Config, jid = RoomJID} = MUCState,
    FromNick) ->
  [{text, _, Body}] = Packet#message.body,
  if
    Body /= "" ->
      _LIST_SUBSCRIBER = get_users_and_subscribers(MUCState),
      GroupId = binary_to_list(RoomJID#jid.luser),
      maps:fold(
        fun(_, #user{jid = To}, _) ->
          group_chat_push(From, To, Packet, GroupId, MUCState, Body)
        end, ok, _LIST_SUBSCRIBER),
      Packet;
    true ->
      Packet
  end.

post_offline_message(From, To, Body, MsgId) ->
  ToUser = binary_to_list(To#jid.luser),
  FromUser = binary_to_list(From#jid.luser),
  FinalBody = binary_to_list(Body),
  MessageId = binary_to_list(MsgId),
  TypeChat = "chat",
  PostUrl = gen_mod:get_module_opt(To#jid.lserver, ?MODULE, post_url, fun(S) ->
    iolist_to_binary(S) end, list_to_binary("")),
  DataBody = "{\"toJID\":\"" ++ ToUser ++ "\",\"fromJID\":\"" ++ FromUser ++ "\",\"body\":\"" ++ FinalBody ++ "\",\"messageID\":\"" ++ MessageId ++ "\",\"type\":\"" ++ TypeChat ++ "\"}",
  Method = post,
  URL = binary_to_list(PostUrl),
  Header = [],
  Type = "application/json",
  HTTPOptions = [],
  Options = [],
  inets:start(),
  ssl:start(),
  httpc:request(Method, {URL, Header, Type, DataBody}, HTTPOptions, Options).