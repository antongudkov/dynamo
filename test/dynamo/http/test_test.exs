Code.require_file "../../../test_helper.exs", __FILE__

defmodule Dynamo.HTTP.TestTest do
  use ExUnit.Case, async: true

  alias Dynamo.HTTP.Test, as: C

  ## Request

  test :version do
    assert conn(:GET, "/").version == { 1, 1 }
  end

  test :method do
    assert conn(:GET, "/").method == "GET"
    assert conn(:POST, "/").method == "POST"

    conn = conn(:GET, "/")
    assert conn.method == "GET"
    assert conn.original_method == "GET"

    conn = conn.method("POST")
    assert conn.method == "POST"
    assert conn.original_method == "GET"
  end

  test :path do
    assert conn(:GET, "/foo/bar").path_segments == ["foo", "bar"]
    assert conn(:GET, "/").path_segments == []

    assert conn(:GET, "/foo/bar").path == "/foo/bar"
    assert conn(:GET, "/").path == "/"
  end

  test :query_string do
    assert conn(:GET, "/foo/bar").query_string == ""
    assert conn(:GET, "/foo/bar?hello=world&foo=bar").query_string == "hello=world&foo=bar"
  end

  test :params do
    conn = conn(:GET, "/foo/bar?hello=world&foo[name]=bar")

    assert_raise Dynamo.HTTP.UnfetchedError, fn ->
      conn.params
    end

    params = conn.fetch(:params).params
    assert params["hello"] == "world"
    assert params["foo"]["name"] == "bar"
  end

  test :req_headers do
    conn = conn(:GET, "/foo/bar")

    assert_raise Dynamo.HTTP.UnfetchedError, fn ->
      conn.req_headers
    end

    conn = conn.set_req_header "X-Code", "123456"
    assert conn.fetch(:headers).req_headers["x-code"] == "123456"

    conn = conn.delete_req_header "X-Code"
    assert conn.fetch(:headers).req_headers["x-code"] == nil
  end

  test :host do
    conn = conn(:GET, "/foo/bar").fetch(:headers)
    assert conn.req_headers["host"] == "127.0.0.1"

    conn = conn(:GET, "//example.com:4000/foo/bar").fetch(:headers)
    assert conn.req_headers["host"] == "example.com:4000"
  end

  test :req_body do
    conn = conn(:POST, "/foo/bar", "foobar")

    assert_raise Dynamo.HTTP.UnfetchedError, fn ->
      conn.req_body
    end

    assert conn.fetch(:body).req_body == "foobar"
  end

  ## Cookies

  test :req_cookies do
    conn = conn(:GET, "/").req_cookies(foo: "bar", baz: "bat")
    assert conn.req_cookies["foo"] == "bar"
    assert conn.req_cookies["baz"] == "bat"
    conn
  end

  test :cookies do
    conn = conn(:GET, "/").req_cookies(foo: "bar", baz: "bat").fetch(:cookies)
    assert conn.cookies["foo"] == "bar"
    assert conn.cookies["baz"] == "bat"
    conn
  end

  test :resp_cookies do
    conn = conn(:GET, "/")
    assert conn.resp_cookies == []

    conn = conn.set_cookie(:foo, :bar, path: "/hello")
    assert conn.resp_cookies == [{ "foo", "bar", path: "/hello" }]
  end

  test :req_resp_cookies do
    conn = conn(:GET, "/").req_cookies(foo: "bar", baz: "bat").fetch(:cookies)
    assert conn.cookies["foo"] == "bar"
    assert conn.cookies["baz"] == "bat"

    conn = conn.set_cookie(:foo, :new)
    assert conn.cookies["foo"] == "new"
    assert conn.cookies["baz"] == "bat"

    conn = conn.delete_cookie(:foo)
    assert conn.cookies["foo"] == nil
  end

  ## Response

  test :send do
    conn = conn(:GET, "/")
    assert conn.state == :unset

    conn = conn.send(201, "OK")
    assert conn.state  == :sent
    assert conn.status == 201
  end

  test :send_with_head do
    conn = conn(:HEAD, "/")

    assert_raise Dynamo.HTTP.InvalidSendOnHeadError, fn ->
      conn.send(200, "HELLO")
    end

    conn.send(200, "")
  end

  test :sendfile do
    file = File.expand_path("../../../fixtures/static/file.txt", __FILE__)
    conn = conn(:GET, "/").sendfile(file)
    assert conn.state     == :sent
    assert conn.status    == 200
    assert conn.resp_body == "HELLO"
    conn
  end

  test :status do
    conn = conn(:GET, "/")
    assert conn.state == :unset

    conn = conn.status(201)
    assert conn.state  == :set
    assert conn.status == 201
  end

  test :resp_body do
    conn = conn(:GET, "/")
    assert conn.state == :unset

    conn = conn.resp_body("OK")
    assert conn.state     == :set
    assert conn.resp_body == "OK"
  end

  test :resp_content_type_and_charset do
    conn = conn(:GET, "/").send(200, "OK")
    assert conn.resp_headers["content-type"] == nil

    conn = conn(:GET, "/").resp_content_type("application/json").send(200, "OK")
    assert conn.resp_headers["content-type"] == "application/json; charset=utf-8"
  end

  ## Misc

  test :assigns do
    conn  = conn(:GET, "/")
    assert conn.assigns == []

    conn = conn.assign :foo, "bar"
    assert conn.assigns == [foo: "bar"]

    conn = conn.assign :foo, "baz"
    assert conn.assigns == [foo: "baz"]
  end

  test :forward_to do
    conn = conn(:GET, "/forward_to/foo/bar/baz")
    assert conn.path_segments == ["forward_to", "foo", "bar", "baz"]

    conn = conn.forward_to ["forward_to", "foo", "bar", "baz"], Foo
    assert conn.path_segments == ["forward_to", "foo", "bar", "baz"]

    conn = conn.forward_to ["foo", "bar", "baz"], Foo

    assert conn.path_info == "/foo/bar/baz"
    assert conn.path_info_segments == ["foo", "bar", "baz"]

    assert conn.path == "/forward_to/foo/bar/baz"
    assert conn.path_segments == ["forward_to", "foo", "bar", "baz"]

    assert conn.script_name == "/forward_to"
    assert conn.script_name_segments == ["forward_to"]

    conn = conn.forward_to ["bar", "baz"], Bar

    assert conn.path_info == "/bar/baz"
    assert conn.path_info_segments == ["bar", "baz"]

    assert conn.path == "/forward_to/foo/bar/baz"
    assert conn.path_segments == ["forward_to", "foo", "bar", "baz"]

    assert conn.script_name == "/forward_to/foo"
    assert conn.script_name_segments == ["forward_to", "foo"]

    conn = conn.forward_to [], Bar

    assert conn.path_info == "/"
    assert conn.path_info_segments == []

    assert conn.path == "/forward_to/foo/bar/baz"
    assert conn.path_segments == ["forward_to", "foo", "bar", "baz"]

    assert conn.script_name == "/forward_to/foo/bar/baz"
    assert conn.script_name_segments == ["forward_to", "foo", "bar", "baz"]

    conn
  end

  defp conn(verb, path, body // "") do
    C.new.req(verb, path, body)
  end
end
