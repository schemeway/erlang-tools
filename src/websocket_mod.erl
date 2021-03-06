%%% File    : websocket_mod.erl
%%% Author  : Dominique Boucher <>
%%% Description : Websockets module for Yaws and behaviour

-module(websocket_mod).


-export([out/1, setup/2, cast/1, cast/2]).
-export([behaviour_info/1]).


-include("yaws_api.hrl").


-define(HANDLER_MODULE_PARAMETER, "websocket_handler").
-define(MSG_TAG,'$ws_msg').


behaviour_info(callbacks) ->
    [{init, 1}, {handle_data, 2}, {handle_info, 2}, {terminate, 1}];
behaviour_info(_Other) ->
    undefined.


cast(WsProcess, Event) ->
    WsProcess ! {?MSG_TAG, Event}.

cast(Event) ->
    cast(self(), Event).


out(A) ->
    case get_handler(A) of
	{module, HandlerModule} ->
	    setup(A, HandlerModule);
	_ ->
	    {content, "text/plain", "Undefined websocket handler module"}
    end.


setup(A, HandlerModule) -> 
    case get_upgrade_header(A#arg.headers) of 
	undefined ->
	    error_logger:info_msg("Receive a request from a non-websocket client~n"),
	    {content, "text/plain", "You're not a web sockets client! Go away!"};
	"WebSocket" ->
	    WebSocketOwner = spawn(fun() -> init_handler(HandlerModule, A) end),
	    {websocket, WebSocketOwner, passive}
    end.


get_handler(Arg) ->
    Opaque = Arg#arg.opaque,
    case lists:keysearch(?HANDLER_MODULE_PARAMETER, 1, Opaque) of
	{value, {_, Value}} ->
	    HandlerModule = list_to_atom(Value),
	    {module, HandlerModule};
	_ ->
	    error
    end.


init_handler(HandlerModule, HttpArgs) ->
    receive
	{ok, WebSocket} ->
	    yaws_api:websocket_setopts(WebSocket, [{active, true}]),
	    State = HandlerModule:init(HttpArgs),
	    event_loop(HandlerModule, WebSocket, State);
	_ -> 
            HandlerModule:terminate([]),
	    ok
    end.

event_loop(HandlerModule, WebSocket, State) ->
    receive
	{tcp, WebSocket, DataFrame} ->
	    Messages = yaws_websockets:unframe_all(DataFrame, []),
	    NewState = 
		lists:foldl(fun(Msg, CurrentState) ->
                                    HandlerModule:handle_data(Msg, CurrentState)
			    end, State, Messages),
            event_loop(HandlerModule, WebSocket, NewState);
	{tcp_closed, WebSocket} ->
            HandlerModule:terminate(State),
	    bye;
	{?MSG_TAG, Event} ->
	    process_message(Event, HandlerModule, handle_info, WebSocket, State);
	Msg ->
	    process_message(Msg, HandlerModule, handle_info, WebSocket, State)
    end.


process_message(Message, HandlerModule, HandlerFunction, WebSocket, State) ->
    case HandlerModule:HandlerFunction(Message, State) of
	{json, JsonObject, NewState} ->
	    Data = list_to_binary(json:encode(JsonObject)),	
	    yaws_api:websocket_send(WebSocket, Data),
	    event_loop(HandlerModule, WebSocket, NewState);
	{raw, Data, NewState} when is_binary(Data) ->
	    yaws_api:websocket_send(WebSocket, Data),
	    event_loop(HandlerModule, WebSocket, NewState);
	ignore ->
	    event_loop(HandlerModule, WebSocket, State);
	Result ->
	    error_logger:warning_msg("Unhandled result in websocket handler: ~p", [Result]),
	    event_loop(HandlerModule, WebSocket, State)
    end.
	    

get_upgrade_header(#headers{other=L}) ->
    lists:foldl(fun({http_header,_,K0,_,V}, undefined) ->
                        K = case is_atom(K0) of
                                true ->
                                    atom_to_list(K0);
                                false ->
                                    K0
                            end,
                        case string:to_lower(K) of
                            "upgrade" ->
                                V;
                            _ ->
                                undefined
                        end;
                   (_, Acc) ->
                        Acc
                end, undefined, L).
