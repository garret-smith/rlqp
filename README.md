rlqp
====

Rate-limiting Queue Processor

Basic problem
----

Many clients need to access a service or resource (possibly one external to the Erlang VM).
If the service/resource receives too many requests in a short period, it may go "boom".
Requests must be throttled to an acceptable rate to prevent overload.

Solution
----

rlqp acts as a "shim" between the service/resource that needs to be protected from overload and the clients.
While a gen_server would be a perfect solution, it is also overkill.  rlqp gets rid of the reams of boilerplate and gives you just enough to put messages into a queue and process them at a fixed rate.

