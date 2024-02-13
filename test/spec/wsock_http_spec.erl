%Copyright [2012] [Farruco Sanjurjo Arcay]

%   Licensed under the Apache License, Version 2.0 (the "License");
%   you may not use this file except in compliance with the License.
%   You may obtain a copy of the License at

%       http://www.apache.org/licenses/LICENSE-2.0

%   Unless required by applicable law or agreed to in writing, software
%   distributed under the License is distributed on an "AS IS" BASIS,
%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%   See the License for the specific language governing permissions and
%   limitations under the License.

-module(wsock_http_spec).
-include_lib("espec/include/espec.hrl").
-include_lib("hamcrest/include/hamcrest.hrl").
-include("wsock.hrl").

spec() ->
  describe("build", fun() ->
        it("should build proper HTTP messages", fun() ->
              RequestLine = [
                {method, "GET"},
                {version, "1.1"},
                {resource, "/"}
              ],

              Headers = [
                {"Header-A", "A"},
                {"Header-B", "B"}
              ],

              Message = wsock_http:build(request, RequestLine, Headers),

              assert_that(Message#http_message.type, is(request)),

              assert_that(proplists:get_value(method, Message#http_message.start_line), is("GET")),
              assert_that(proplists:get_value(version, Message#http_message.start_line), is("1.1")),
              assert_that(proplists:get_value(resource, Message#http_message.start_line), is("/")),
              assert_that(proplists:get_value("Header-A", Message#http_message.headers), is("A")),
              assert_that(proplists:get_value("Header-B", Message#http_message.headers), is("B"))
          end)
    end),
  describe("get_start_line_value", fun() ->
        it("should return http_message start_line values if present", fun() ->
              Message = #http_message{
                type = request,
                start_line = [
                  {method, "GET"},
                  {version, "1.1"},
                  {resource, "/"}
                ],
                headers = [
                  {"header-a", "A"},
                  {"header-b", "b"}
                ]
              },

              assert_that(wsock_http:get_start_line_value(version, Message), is("1.1")),
              assert_that(wsock_http:get_start_line_value(method, Message), is("GET")),
              assert_that(wsock_http:get_start_line_value(resource, Message), is("/"))
          end)
    end),
  describe("get_header_value", fun() ->
        it("should return http_message header values if present", fun() ->
              Message = #http_message{
                type = request,
                start_line = [
                  {method, "GET"},
                  {version, "1.1"},
                  {resource, "/"}
                ],
                headers = [
                  {"Header-a", "A"},
                  {"header-B", "b"}
                ]
              },

              assert_that(wsock_http:get_header_value("header-a", Message), is("A")),
              assert_that(wsock_http:get_header_value("header-b", Message), is("b"))
          end)
    end),
  describe("encode", fun() ->
        describe("requests", fun() ->
              it("should return a string representating a http request", fun() ->
                    RequestLine = [
                      {method, "GET"},
                      {version, "1.1"},
                      {resource, "/"}
                    ],

                    Headers = [
                      {"Header-A", "A"},
                      {"Header-B", "B"}
                    ],

                    %Message = wsock_http:build(request, RequestLine, Headers),
                    Message = #http_message{ type = request, start_line = RequestLine, headers = Headers },
                    Request = wsock_http:encode(Message),

                    assert_that(Request, is([
                          "GET / HTTP/1.1\r\n",
                          "Header-A: A\r\n",
                          "Header-B: B\r\n",
                          "\r\n"
                        ]))
                end),
              it("should return an error if some field is missing")
          end),
        describe("responses", fun() ->
              it("should return a string representating a http response", fun() ->
                    StartLine = [
                      {version, "1.1"},
                      {status, "101"},
                      {reason, "Switching protocols"}
                    ],

                    Headers = [
                      {"Header-A", "A"},
                      {"Header-B", "B"}
                    ],

                    Message = #http_message{ type = response, start_line = StartLine, headers = Headers},
                    Response = wsock_http:encode(Message),

                    assert_that(Response, is([
                          "HTTP/1.1 101 Switching protocols\r\n",
                          "Header-A: A\r\n",
                          "Header-B: B\r\n",
                          "\r\n"])
                    )
                end),
              it("should return an error if some field is missing")
          end)
    end),
  describe("decode", fun()->
        describe("requests", fun() ->
              it("should return a http_message record of type request", fun() ->
                Data = <<"GET / HTTP/1.1\r\nHost : www.example.org\r\nUpgrade : websocket\r\nSec-WebSocket-Key : ----\r\nHeader-D: D\r\n\r\n">>,

                {ok, Message} = wsock_http:decode(Data, request),

                assert_that(Message#http_message.type, is(request)),

                assert_that(wsock_http:get_start_line_value(method, Message), is("GET")),
                assert_that(wsock_http:get_start_line_value(resource, Message), is("/")),
                assert_that(wsock_http:get_start_line_value(version, Message), is("1.1")),

                assert_that(wsock_http:get_header_value("host", Message), is("www.example.org")),
                assert_that(wsock_http:get_header_value("upgrade", Message), is("websocket")),
                assert_that(wsock_http:get_header_value("sec-websocket-key", Message), is("----")),
                assert_that(wsock_http:get_header_value("header-d", Message), is("D")),
                assert_that(wsock_http:get_header_value("non-existant-header", Message), is(undefined))

            end),
          it("should return an error if the message startline is malformed", fun() ->
                %Missing HTTP method
                Data = <<" / HTTP/1.1\r\nHost : www.example.org\r\nUpgrade : websocket\r\nSec-WebSocket-Key : ----\r\nHeader-D: D\r\n\r\n">>,

            Response = wsock_http:decode(Data, request),

            assert_that(Response, is({error, malformed_request}))
        end ),
      it("should return an error if some header is malformed", fun() ->
            %missing ":" in Upgrade header
            Data = <<"GET / HTTP/1.1\r\nHost : www.example.org\r\nUpgrade  websocket\r\nHeader-D: D\r\n\r\n">>,

        Response = wsock_http:decode(Data, request),

        assert_that(Response, is({error, malformed_request}))
    end),
  describe("should handle fragmented http requests", fun() ->
        it("should handle a request with only a chunk of the startline", fun() ->
              Data = <<"GET / ">>,

              Response = wsock_http:decode(Data, request),
              assert_that(Response, is(fragmented_http_message))
          end),
        it("should handle a request with fragmented headers", fun() ->
              Data = <<"GET / HTTP/1.1\r\nHost">>,

              Response = wsock_http:decode(Data, request),
              assert_that(Response, is(fragmented_http_message))
          end)
    end)
end),
describe("responses", fun() ->
      it("should return a http_message record of type response", fun() ->
            Data = <<"HTTP/1.1 205 Reset Content\r\nHeader-A: A\r\nHeader-C: dGhlIHNhbXBsZSBub25jZQ==\r\nHeader-D: D\r\n\r\n">>,

            {ok, Message} = wsock_http:decode(Data, response),

            assert_that(Message#http_message.type, is(response)),

            assert_that(wsock_http:get_start_line_value(version, Message), is("1.1")),
            assert_that(wsock_http:get_start_line_value(status, Message), is("205")),
            assert_that(wsock_http:get_start_line_value(reason, Message), is("Reset Content")),

            assert_that(wsock_http:get_header_value("header-a", Message), is("A")),
            assert_that(wsock_http:get_header_value("header-c", Message), is("dGhlIHNhbXBsZSBub25jZQ==")),
            assert_that(wsock_http:get_header_value("header-d", Message), is("D"))
        end),
      it("should return an error if the message startline is malformed", fun() ->
            Data = <<"HTTP/1.1  Reset Content\r\nHeader-A: A\r\nHeader-C: dGhlIHNhbXBsZSBub25jZQ==\r\nHeader-D: D\r\n\r\n">>,

            Response = wsock_http:decode(Data, response),

            assert_that(Response, is({error, malformed_request}))
        end),
      it("should return an error if some header is malformed", fun() ->
            Data = <<"HTTP/1.1 205 Reset Content\r\nHeader-A: A\r\nHeader-C  dGhlIHNhbXBsZSBub25jZQ==\r\nHeader-D: D\r\n\r\n">>,

            Response = wsock_http:decode(Data, response),

            assert_that(Response, is({error, malformed_request}))
        end),
      describe("should handle fragmented http responses", fun() ->
            it("should handle a response with only a chunk of the status line", fun() ->
                  Data = <<"HTTP/1.1 205">>,

                  Response = wsock_http:decode(Data, response),
                  assert_that(Response, is(fragmented_http_message))
              end),
            it("should handle a response with fragmented headers", fun() ->
                  Data = <<"HTTP/1.1 200 OK\r\nContent-type">>,

                  Response = wsock_http:decode(Data, response),
                  assert_that(Response, is(fragmented_http_message))
              end)
        end)
  end)
end).
