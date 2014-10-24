open Lwt
open Cohttp
open Cohttp.Code
open Cohttp_lwt_unix

open Inbox_app

open Nlencoding

exception Error_code of Cohttp.Code.status_code

(** Default URIs, suitable for hosted Inbox instances. *)
let api_uri  = Uri.of_string "https://api.inboxapp.com"
let base_uri = Uri.of_string "https://www.inboxapp.com"

let api_path { api_uri } path = Uri.with_path api_uri path

let authentication_uri app user_email redirect_uri =
  let uri = Uri.with_path app.base_uri "oauth/authorize" in
  Uri.add_query_params' uri [
    ("client_id", app.app_id);
    ("response_type", "code");
    ("scope", "email");
    ("login_hint", user_email);
    ("redirect_uri", Uri.to_string redirect_uri)
  ]

let call_string http_method ?access_token uri =
  let headers = match access_token with
    | Some token ->
       let basic_auth = Base64.encode (token ^ ":") in
       Printf.printf "Basic auth: %s\n" basic_auth;
       flush stdout;
       Header.init_with "Authorization" ("Basic " ^ basic_auth)
    | None       -> Header.init ()
  in
  Client.call ~headers http_method uri >>= fun (response, body) ->
  match response.Client.Response.status, body with
  | `OK, `Stream body -> Lwt_stream.fold (^) body ""
  | `OK, `Empty       -> return ""
  | err, `Stream body -> Lwt_stream.fold (^) body ""
  | err, _            -> raise (Error_code err)

let call_parse http_method parse_fn ?access_token uri =
  call_string ?access_token http_method uri >>= fun body ->
  Lwt.return (parse_fn body)

let post_authentication_code app code =
  (* NOTE: The leading slash in /oauth/token is necessary. *)
  let base = Uri.with_path app.base_uri "/oauth/token" in
  let uri  = Uri.add_query_params' base [
      ("client_id", app.app_id);
      ("client_secret", app.app_secret);
      ("grant_type", "authorization_code");
      ("code", code)
    ]
  in
  call_parse `POST Inbox_j.authentication_result_of_string uri

let get_namespaces ~access_token ~app =
  call_parse ~access_token `GET Inbox_j.namespace_list_of_string (api_path app "/n")

let get_namespace ~access_token ~app id  =
  let uri = api_path app ("/n/" ^ id) in
  call_parse ~access_token `GET Inbox_j.namespace_of_string uri

let get_calendars ~access_token ~app namespace_id =
  let uri = api_path app ("/n/" ^ namespace_id ^ "/calendars") in
  call_parse ~access_token `GET Inbox_j.calendar_list_of_string uri

let get_event ~access_token ~app namespace_id event_id =
  let uri = api_path app ("/n/" ^ namespace_id ^ "/events/" ^ event_id) in
  call_parse ~access_token `GET Inbox_j.event_of_string uri

let get_events ~access_token ~app namespace_id filters =
  let uri =
    Filter.filter filters (api_path app ("/n/" ^ namespace_id ^ "/events"))
  in
  call_parse ~access_token `GET Inbox_j.event_list_of_string uri
