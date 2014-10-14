open Lwt
open Cohttp.Code
open Cohttp_lwt_unix

exception Error_code of Cohttp.Code.status_code

type app = {
  api_uri    : Uri.t;
  base_uri   : Uri.t;
  app_id     : string;
  app_secret : string;
}

let authentication_uri app user_email redirect_uri =
  Uri.add_query_params' app.base_uri [
    ("client_id", app.app_id);
    ("response_type", "code");
    ("scope", "email");
    ("login_hint", user_email);
    ("redirect_uri", Uri.to_string redirect_uri)
  ]

let post_authentication_code app code =
  let uri = Uri.add_query_params' app.base_uri [
      ("client_id", app.app_id);
      ("client_secret", app.app_secret);
      ("grant_type", "authorization_code");
      ("code", code)
    ]
  in
  Client.post uri

let call_string http_method ?access_token uri =
  let uri = match access_token with
    | Some token -> Uri.add_query_param' uri ("access_token", token)
    | None       -> uri
  in
  Client.call http_method uri >>= fun (response, body) ->
  match response.Client.Response.status, body with
  | `OK, `Stream body -> Lwt_stream.fold (^) body ""
  | `OK, `Empty       -> return ""
  | err, _            -> raise (Error_code err)

let get_namespaces () = call_string `GET (Uri.of_string "https://api.inbox.com/n")

let get_namespace id = failwith "undefined"