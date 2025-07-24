(** Model Context Protocol implementation for OCaml.

    This library implements the Model Context Protocol (MCP), enabling seamless
    integration between AI models and development tools. MCP provides a standard
    interface for AI assistants to access context from development environments,
    file systems, and other data sources.

    {1 Architecture}

    The protocol follows a client-server model where:
    - Clients (AI models) connect to servers
    - Servers expose tools, resources, and prompts
    - Communication uses JSON-RPC over configurable transports

    {1 Core Modules} *)

module Types = Mcp_types
(** Protocol types and data structures. *)

module Request = Mcp_request
(** Request types and handlers. *)

module Notification = Mcp_notification
(** Notification types and handlers. *)

module Protocol = Mcp_protocol
(** Protocol message handling and JSON-RPC communication. *)

module Server = Mcp_server
(** Server implementation for exposing tools and resources. *)

module Client = Mcp_client
(** Client implementation for connecting to MCP servers. *)

module Meta = Mcp_meta
(** Validator for _meta field keys. *)
