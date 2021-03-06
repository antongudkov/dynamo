defmodule Dynamo.HTTP do
  defrecord File, body: nil, name: nil, content_type: nil, filename: nil do
    @moduledoc """
    Contains a file representation whenever there is a multipart
    request and it contains a File.
    """
  end

  defexception UnfetchedError, aspect: nil do
    def message(exception) do
      aspect = aspect(exception)
      "Did not fetch #{aspect} from request, add `fetch :#{aspect}` in order to access it"
    end
  end

  defexception InvalidSendOnHeadError, message: "Cannot send data because conn.original_method is HEAD"

  @moduledoc """
  This module defines the API implemented by the http
  connection, as in Dynamo.Cowboy.HTTP and Dynamo.HTTP.Test.

  Notice that Dynamo.HTTP connections uses the record
  notation. So although the documentation says `params(conn)`,
  the function should be invoked as `conn.params()` and
  Elixir automatically moves the conn to the last argument.

  It is also important to remind that, as in all Elixir
  structures, a connection is immutable. So if you are using
  `conn.set_resp_header("X-API", "123456")` to set a response
  header, a new connection will be returned with the new header
  set. The original `conn` is not going to be modified.
  """

  @doc """
  Default values for before send callbacks.
  It contains callbacks to set content type,
  configure cookies and session.
  """
  def default_before_send do
    [ set_resp_content_type_header(&1) ]
  end

  defp set_resp_content_type_header(conn) do
    if content_type = conn.resp_content_type do
      if charset = conn.resp_charset do
        content_type = content_type <> "; charset=" <> charset
      end
      conn.set_resp_header("content-type", content_type)
    else
      conn
    end
  end

  @opaque conn         :: tuple
  @type   body         :: binary
  @type   status       :: non_neg_integer
  @type   headers      :: Binary.Dict.t
  @type   method       :: binary
  @type   segments     :: [binary]
  @type   charset      :: binary
  @type   content_type :: binary
  @type   fetch_aspect :: :headers | :params | :cookies | :body | :session
  @type   app          :: module
  @type   assigns      :: list

  use Behaviour

  ## Request API

  @doc """
  Returns the params retrieved from the query string and the request
  body as a `Binary.Dict`. The parameters need to be explicitly
  fetched with `conn.fetch(:params)` before using this function.
  """
  defcallback params(conn), do: Binary.Dict.t | no_return

  @doc """
  Returns the request headers as `Binary.Dict`. Note that duplicated
  entries are removed. The headers need to be explicitly fetched with
  `conn.fetch(:headers)` before using this function. Headers keys are
  all downcased.
  """
  defcallback req_headers(conn), do: headers | no_return

  @doc """
  Returns the request body as a binary.
  """
  defcallback req_body(conn), do: body | no_return

  @doc """
  Returns the HTTP method as a binary.

  ## Examples

      conn.method #=> "GET"

  """
  defcallback method(conn), do: method

  @doc """
  Returns the original HTTP method as a binary.
  Sometimes a filter may change the method from
  HEAD to GET or from POST to PUT, this function
  returns the original method.

  ## Examples

      conn.original_method #=> "GET"

  """
  defcallback original_method(conn), do: method

  @doc """
  Changes the request method to the given `method`,
  storing the previous value in original_method.
  """
  defcallback method(method, conn), do: conn

  @doc """
  Returns the HTTP version.
  """
  defcallback version(conn), do: binary

  ## Paths

  @doc """
  Returns the query string as a binary.
  """
  defcallback query_string(conn), do: binary

  @doc """
  Returns the full path segments, as received by the web server.
  """
  defcallback path_segments(conn), do: [binary]

  @doc """
  Returns the full path as a binary, as received by the web server.
  """
  defcallback path(conn), do: binary

  @doc """
  Return the path as a list of binaries split on "/".
  If the request was forwarded request, `path_info_segments` returns
  only the segments related to the current forwarded endpoint.
  """
  defcallback path_info_segments(conn), do: segments

  @doc """
  Returns the request path relative to the forwarding endpoint
  as a binary.
  """
  defcallback path_info(conn), do: binary

  @doc """
  As in CGI environment, returns the current forwarded endpoint as segments.
  """
  defcallback script_name_segments(conn), do: segments

  @doc """
  As in CGI environment, returns the current forwarded endpoint as binary.
  """
  defcallback script_name(conn), do: binary

  @doc """
  Mounts the request by setting the new path information to the given
  *segments*. Both script_name/1 and path_segments/1 are updated.
  The segments given must be a suffix of the current path segments.
  """
  defcallback forward_to(segments, module, conn), do: conn

  ## Response API

  @doc """
  Sends to the client the given status and body.
  An updated connection is returned with `:sent` state,
  the given status and response body set to nil.
  """
  defcallback send(status, body :: term, conn), do: conn

  @doc """
  Returns the response status if one was set.
  """
  defcallback status(conn), do: status

  @doc """
  Sets the response status and changes the state to `:set`.
  """
  defcallback status(status, conn), do: conn

  @doc """
  Returns the response body if one was set.
  """
  defcallback resp_body(conn), do: body | nil

  @doc """
  Sets the response body and changes the state to `:set`.
  """
  defcallback resp_body(body, conn), do: conn

  @doc """
  Gets the response charset.
  Defaults to "utf-8".
  """
  defcallback resp_charset(conn), do: binary

  @doc """
  Sets the response charset. The charset
  is just added to the response if
  `resp_content_type` is also set.
  """
  defcallback resp_charset(charset, conn), do: conn

  @doc """
  Gets the response content-type.
  """
  defcallback resp_content_type(conn), do: binary | nil

  @doc """
  Sets the response content-type.
  This is sent as a header when the response is sent.
  """
  defcallback resp_content_type(content_type, conn), do: conn

  @doc """
  Sets a response to the given status and body. The
  response will only be sent when `send` is called.

  After calling this function, the state changes to `:set`,
  both `status` and `resp_body` are set.
  """
  defcallback resp(status, body, conn), do: conn

  @doc """
  A shortcut to `conn.send(conn.status, conn.resp_body)`.
  """
  defcallback send(conn), do: conn

  @doc """
  Sends the file at the given path. It is expected that the
  given path exists and it points to a regular file. The
  file is sent straight away.
  """
  defcallback sendfile(path :: binary, conn), do: conn

  @doc """
  Returns the response state. It can be:

  * `:unset` - the response was not configured yet
  * `:set` - the response was set via `conn.resp_body` or `conn.status`
  * `:chunked` - the response is being sent in chunks
  * `:sent` - the response was sent

  """
  defcallback state(conn), do: :unset | :set | :chunked | :sent

  @doc """
  Returns the response headers as `Binary.Dict`.
  """
  defcallback resp_headers(conn), do: Binary.Dict.t

  @doc """
  Sets a response header, overriding any previous value.
  Both `key` and `value` are converted to binary.
  """
  defcallback set_resp_header(key :: Binary.Chars.t, value :: Binary.Chars.t, conn), do: conn

  @doc """
  Deletes a response header.
  """
  defcallback delete_resp_header(key :: Binary.Chars.t, conn), do: conn

  ## Cookies

  @doc """
  Returns the cookies sent in the request as a `Binary.Dict`.
  Cookies need to be explicitly fetched with `conn.fetch(:cookies)`
  before using this function.
  """
  defcallback req_cookies(conn), do: Binary.Dict.t | no_return

  @doc """
  Returns a Binary.Dict with cookies. Cookies need to be explicitly
  fetched with `conn.fetch(:cookies)` before using this function.
  """
  defcallback cookies(conn), do: Binary.Dict.t

  @doc """
  Returns the response cookies as a list of three element tuples
  containing the key, value and given options.
  """
  defcallback resp_cookies(conn), do: [{ binary, binary, list }]

  @doc """
  Sets a cookie with given key and value and the given options.

  ## Options

  * `max_age` - The cookie max-age in seconds. In order to support
    older IE versions, setting `max_age` also sets the Expires header;

  * `secure` - Marks the cookie as secure;

  * `domain` - The domain to which the cookie applies;

  * `path` - The path to which the cookie applies;

  * `http_only` - If the cookie is sent only via http. Default to true;

  """
  defcallback set_cookie(key :: Binary.Chars.t, value :: Binary.Chars.t, conn), do: conn
  defcallback set_cookie(key :: Binary.Chars.t, value :: Binary.Chars.t, opts :: list, conn), do: conn

  @doc """
  Deletes a cookie. The same options given when setting the cookie
  must be given on delete to ensure the browser will pick them up.
  """
  defcallback delete_cookie(key :: Binary.Chars.t, conn), do: conn
  defcallback delete_cookie(key :: Binary.Chars.t, opts :: list, conn), do: conn

  ## Misc

  @doc """
  Responsible for fetching and caching aspects of the response.
  The "fetchable" aspects are: headers, params, cookies, body
  and session.
  """
  defcallback fetch(fetch_aspect, conn), do: conn

  @doc """
  Returns a keywords list with assigns set so far.
  """
  defcallback assigns(conn), do: assigns

  @doc """
  Sets a new assign with the given key and value.
  """
  defcallback assign(key :: atom, value :: term, conn), do: conn

  @doc """
  Returns the application that received the request.
  """
  defcallback app(conn), do: app
end