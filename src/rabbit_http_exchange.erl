%% Copyright
-module(rabbit_http_exchange).
-include_lib("rabbit_common/include/rabbit.hrl").
-include("rabbit_http_exchange.hrl").

-define(EXCHANGE_TYPE_BIN, <<"x-http">>).
-define(VERSION, <<"0.1.0">>).

-behaviour(rabbit_exchange_type).

-rabbit_boot_step({?MODULE,
                  [{description, "exchange type x-http"},
                    {mfa,         {rabbit_registry, register,
                                   [exchange, ?EXCHANGE_TYPE_BIN, ?MODULE]}},
                    {requires,    rabbit_registry},
                    {enables,     kernel_ready}]}).

-export([description/0, serialise_events/0, route/2]).
-export([validate/1, create/2, delete/3, recover/2, policy_changed/3, add_binding/3,
         remove_bindings/3, assert_args_equivalence/2]).

description() ->
    [{name, ?EXCHANGE_TYPE_BIN},
     {description, <<"HTTP publishing exchange">>}].

serialise_events() -> false.

recover(X, _Bs) ->
    create(none, X).

route(X, Delivery) ->
    rabbit_exchange_type_topic:route(X, Delivery).

validate(_X) ->
    ok.

create(transaction, X) ->
    setup_cowboy(X),
    ok;

create(none, _X) ->
    ok.

delete(transaction, X, _Bs) ->
    stop_cowboy(X),
    ok;

delete(none, _X, _Bs) ->
    ok.

policy_changed(_Tx, _X1, _X2) -> ok.

add_binding(Tx, X, B) -> rabbit_exchange_type_topic:add_binding(Tx, X, B).
remove_bindings(Tx, X, Bs) -> rabbit_exchange_type_topic:remove_bindings(Tx, X, Bs).
assert_args_equivalence(X, Args) -> rabbit_exchange:assert_args_equivalence(X, Args).


% ------------------------------------------------------------------------------
get_exchange_info(#exchange{name=Name, arguments=Args}) ->
    {resource, VHost, exchange, Exchange} = Name,
    {VHost, Exchange, Args}.

get_ref(VHost, Port) ->
    list_to_atom("http_" ++ binary_to_list(VHost) ++ "_" ++ integer_to_list(Port)).

get_port(Args) ->
  case rabbit_misc:table_lookup(Args, <<"port">>) of
    {_, 0} ->
      rabbit_misc:protocol_error(precondition_failed,
                                 "'port' argument must be non-zero", []);
    {_, N} when is_integer(N) ->
      N;
    undefined ->
      rabbit_misc:protocol_error(precondition_failed,
                                 "No 'port' argument specified", []);
    _ ->
      rabbit_misc:protocol_error(precondition_failed,
                                 "'port' must be a numeric value", [])
  end.

setup_cowboy(X) ->
    {VHost, Exchange, Args} = get_exchange_info(X),
    Port = get_port(Args),
    Routes = [{'_', [{[key, '...'], rabbit_http_exchange_publish,
                      [{exchange, X},
                       {name, Exchange},
                       {vhost, VHost}]}]}],
    cowboy:start_listener(get_ref(VHost, Port), 2048,
                          cowboy_tcp_transport, [{port,     Port}],
                          cowboy_http_protocol, [{dispatch, Routes}]),
    rabbit_log:info("Started ~s exchange ~s on virtual host ~s on port ~p~n",
                    [?EXCHANGE_TYPE_BIN, Exchange, VHost, Port]).

stop_cowboy(X) ->
    {Exchange, VHost, Args} = get_exchange_info(X),
    Port = get_port(Args),
    cowboy:stop_listener(get_ref(VHost, Port)),
    rabbit_log:info("Stopped ~s exchange ~s on virtual host ~s on port ~p~n",
                    [?EXCHANGE_TYPE_BIN, Exchange, VHost, Port]).
