(** Eio-based transports for MCP.

    This library provides transport implementations using Eio for efficient
    concurrent I/O in Model Context Protocol applications.

    {1 Modules}

    {!Transport} - Transport interface definition

    {!Stdio} - Standard I/O transport

    {!Socket} - TCP and Unix domain socket transport

    {!Memory} - In-memory transport for testing

    {!Http} - HTTP transport for server and client

    {!Connection} - Connection lifecycle management

    {!Framing} - JSON-RPC message framing *)

module Transport = Transport
module Stdio = Transport_stdio
module Socket = Transport_socket
module Memory = Transport_memory
module Http = Transport_http
module Connection = Connection
module Framing = Framing
module Logging = Logging
