%%%
%%% @author Garret Smith <garret.smith@gmail.com>
%%%
%%% @doc rlqp - rate-limiting queue processor
%%% <p>
%%% Collect messages/calls from multiple clients and then process/forward
%%% them at a constant rate.
%%% Designed to collect calls (potentially bursty) from many Erlang processes
%%% and forward them to an external non-Erlang client that would go "boom" if
%%% it got flooded with requests.
%%% </p>
%%% <p>
%%% The user module should export
%%% <code>
%%%     process(term()) -> {reply, term()} | noreply .
%%% </code>
%%% </p>
%%% @end

-module(rlqp).


-behavior(gen_server).


-export([start_link/4, start_link/3, sync_enqueue/2, async_enqueue/2, newrate/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).


-callback process(term()) -> {reply, term()} | noreply .


-record(qp, {
		mod :: atom(),
		q :: queue(),
		rate :: integer()
	}).


start_link(Name, Mod, Rate) ->
	start_link(Name, Mod, Rate, [])
	.

start_link(Name, Mod, Rate, Options) ->
	gen_server:start_link(Name, ?MODULE, {Mod, Rate}, Options)
	.

%%% @doc
%%% Queue up a synchronous call.  The call will never time out.
%%% @end
sync_enqueue(Name, Term) ->
	gen_server:call(Name, Term, infinity)
	.

%%% @doc
%%% Queue up an async message.
%%% @end
async_enqueue(Name, Term) ->
	gen_server:cast(Name, {enqueue, Term})
	.

%%% @doc
%%% Change the rate at which messages are processed from the queue (delay between them).
newrate(Name, Rate) ->
	gen_server:cast(Name, {newrate, Rate})
	.

%% Behavior callbacks
init({CallbackModule, Rate}) ->
	send_after(Rate),
	{ok, #qp{mod = CallbackModule, q = queue:new(), rate = Rate}}
	.

handle_call({enqueue, Term}, From, State = #qp{q = Q}) ->
	{noreply, State#qp{q = queue:in({Term, From}, Q)}}
	;
handle_call(Message, From, State) ->
	lager:error("Unexpected handle_call. message: ~p, from: ~p, state: ~p", [Message, From, State]),
	{reply, huh, State}
	.

handle_cast({newrate, NewRate}, State) ->
	{noreply, State#qp{rate = NewRate}}
	;
handle_cast({enqueue, Term}, State = #qp{q = Q}) ->
	{noreply, State#qp{q = queue:in({Term, none}, Q)}}
	;
handle_cast(Request, State) ->
	lager:error("Unexpected handle_cast. request: ~p, state: ~p", [Request, State]),
	{noreply, State}
	.

handle_info(check_q, State = #qp{q = Q, rate = Rate, mod = Mod}) ->
	Q2 = case queue:out(Q) of
		{empty, Q1} -> Q1;
		{{value, {Term, Reply}}, Q1} ->
			do_process(Mod, Term, Reply),
			Q1
	end,
	send_after(Rate),
	{noreply, State#qp{q = Q2}}
	;
handle_info(Info, State) ->
	lager:error("Unexpected handle_info. info: ~p, state: ~p", [Info, State]),
	{noreply, State}
	.

terminate(Reason, State) ->
	lager:info("terminating... reason: ~p, state: ~p", [Reason, State])
	.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}
	.


%% utility functions

do_process(Mod, Term, ReplyTo) ->
	case Mod:process(Term) of
		noreply -> ok;
		{reply, Reply} when ReplyTo /= none ->
			gen_server:reply(ReplyTo, Reply);
		{reply, _} ->
			error_logger:warning_report("callback returned a reply, but no client is waiting")
	end
	.

send_after(T) ->
	erlang:send_after(T, self(), check_q)
	.

