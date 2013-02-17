%% ----------------------------------------------
%% Accept either a POST or PUT of a message to
%% be published to RabbitMQ
%%
%% When posting JSON data the payload format is:
%%
%% uri: /<routing-key>
%% content-type: application/json
%%
%% {
%%   "properties": {
%%     "app_id": null,
%%     "content_encoding": null,
%%     "content_type": null,
%%     "correlation_id": null,
%%     "delivery_mode": null,
%%     "expiration": null,
%%     "headers": null,
%%     "message_id": null,
%%     "priority": null,
%%     "timestamp": null,
%%     "type": null,
%%     "user_id": null,
%%   },
%%   "body": null
%% }
%%
%% content-type: application/x-www-form-urlencoded
%%
%%    POST body: content_type=application%2Fjson&body=test
%%
%% ----------------------------------------------
-module(rabbit_http_exchange_publish).
-include_lib("rabbit_common/include/rabbit.hrl").
-include_lib("rabbit_common/include/rabbit_framing.hrl").
-include("rabbit_http_exchange.hrl").

-export([init/3]).
-export([handle/2]).
-export([terminate/2]).

init(_, Req, Options) ->
    {ok, Req, Options}.

handle(Req, State) ->
    case cowboy_http_req:method(Req) of
        {'POST', _} ->
            % State1 = process_authentication(Req, State);
            process_content_type(Req, State);
        {'PUT', _} ->
            % State1 = process_authentication(Req, State);
            process_content_type(Req, State);
        _ ->
            cowboy_http_req:reply(405, Req)
    end,
    {ok, Req, State}.

terminate(_Req, _Service) ->
  ok.

%% ----------------------------------------------

deliver(X, Delivery) ->
    QueueNames = rabbit_exchange_type_topic:route(X, Delivery),
    Queues = rabbit_amqqueue:lookup(QueueNames),
    {routed, _} = rabbit_amqqueue:deliver(Queues, Delivery),
    ok.

form_encoded_body_value(Values, Key) ->
    proplists:get_value(Key, Values).

get_routing_key(Req) ->
    {Key, _} = cowboy_http_req:binding(key, Req),
    Key.

get_value(Options, Key) ->
    proplists:get_value(Options, Key, undefined).

init_state(Options) ->
    #rabbit_http_exchange_state{exchange=get_value(Options, exchange),
                                virtual_host=get_value(Options, virtual_host),
                                username=get_value(Options, username),
                                password=get_value(Options, password)}.

process_content_type(Req, State) ->
    case cowboy_http_req:parse_header('Content-Type', Req) of
        {{<<"application">>,<<"json">>,[]}, _} ->
            process_json_request(Req, State);
        {{<<"application">>,<<"x-www-form-urlencoded">>,[]}, _} ->
            process_form_encoded_request(Req, State);
        _ ->
            cowboy_http_req:reply(406, Req)
    end.

parse_payload({<<"body">>, Body}) ->
    {body, Body};

parse_payload({<<"properties">>, {struct, Properties}}) ->
    {properties, Properties};

parse_payload(Value) ->
    rabbit_log:error("Did not match parse payload: ~p~n", [Value]),
    {error, null}.

json_decode(Value) ->
    try
        {struct, Decoded} = mochijson2:decode(binary_to_list(Value)),
        {ok, Decoded}
    catch error:_ -> {error, not_json}
    end.

process_json_request(Req, State) ->
    {ok, PostBody, _} = cowboy_http_req:body(Req),
    case json_decode(PostBody) of
        {ok, JSON} ->
            Parts = [parse_payload(Values) || Values <- JSON],
            Body = proplists:get_value(body, Parts),
            Properties = proplists:get_value(properties, Parts),
            publish_message(State, Req, Properties, Body);
        {error, not_json} ->
            Message = io_lib:format("ERROR: Could not decode POST body: ~p",
                                    [PostBody]),
            rabbit_log:info("", [PostBody]),
            cowboy_http_req:reply(400, [], Message, Req)
        end.

process_form_encoded_request(Req, State) ->
    {Values, _} = cowboy_http_req:body_qs(Req),
    Body = form_encoded_body_value(Values, <<"body">>),
    Properties = [{Key, form_encoded_body_value(Values, Key)} || Key <- record_info(fields, 'P_basic'),
                  form_encoded_body_value(Values, Key) /= undefined],
    publish_message(State, Req, Properties, Body).

basic_properties(Properties) ->
    Keys = [erlang:list_to_binary(Key) || Key <- [erlang:atom_to_list(Key) || Key <- record_info(fields, 'P_basic')]],
    list_to_tuple(['P_basic'|[proplists:get_value(Key, Properties) || Key <- Keys]]).

publish_message(State, Req, Properties, Body) ->
    Exchange = proplists:get_value(name, State),
    Resource = proplists:get_value(exchange, State),
    RoutingKey = get_routing_key(Req),
    Props = basic_properties(Properties),
    try
        rabbit_basic:publish(Resource, RoutingKey, false, Props, Body),
        cowboy_http_req:reply(204, Req)
    catch throw:Error ->
        Message = io_lib:format("ERROR: Could not publish: ~p", [Error]),
        rabbit_log:error(Message),
        cowboy_http_req:reply(400, [], Message, Req)
    end.
