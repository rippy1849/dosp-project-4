import gleam/dict
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/actor

pub type State {
  State(
    internal: #(Int),
    stack: List(String),
    users_db: dict.Dict(String, String),
    subreddit_user_db: dict.Dict(String, List(String)),
    subreddit_comment_db: dict.Dict(String, List(#(String, String, String))),
  )
}

pub type Message {
  Shutdown
  SetInternal(#(Int))
  RegisterAccount(String, String)
  CreateSubReddit(String)
  JoinSubReddit(String, String)
  LeaveSubReddit(String, String)
  Post(String, String, String)
  Comment(String, String, String, String)
  // Push(String)
  // PopGossip(process.Subject(Result(Int, Nil)))
}

fn handle_message(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    Shutdown -> actor.stop()
    SetInternal(#(v1)) -> {
      actor.continue(State(
        #(v1),
        state.stack,
        state.users_db,
        state.subreddit_user_db,
        state.subreddit_comment_db,
      ))
    }
    RegisterAccount(username, password) -> {
      let users_db = dict.insert(state.users_db, username, password)

      actor.continue(State(
        state.internal,
        state.stack,
        users_db,
        state.subreddit_user_db,
        state.subreddit_comment_db,
      ))
    }
    CreateSubReddit(subreddit_name) -> {
      let subreddit_user_db =
        dict.insert(state.subreddit_user_db, subreddit_name, [])
      //TODO What if subreddit already exists?

      let result = dict.get(subreddit_user_db, subreddit_name)

      let list_check = case result {
        Ok(result) -> result
        Error(_) -> []
      }

      // echo list_check
      let is_empty = list.is_empty(list_check)

      actor.continue(State(
        state.internal,
        state.stack,
        state.users_db,
        subreddit_user_db,
        state.subreddit_comment_db,
      ))
    }
    JoinSubReddit(subreddit_name, username) -> {
      let subreddit_db =
        add_to_list_in_dict(state.subreddit_user_db, subreddit_name, username)

      actor.continue(State(
        state.internal,
        state.stack,
        state.users_db,
        subreddit_db,
        state.subreddit_comment_db,
      ))
    }
    LeaveSubReddit(subreddit_name, username) -> {
      let subreddit_db =
        remove_from_list_in_dict(
          state.subreddit_user_db,
          subreddit_name,
          username,
        )

      actor.continue(State(
        state.internal,
        state.stack,
        state.users_db,
        subreddit_db,
        state.subreddit_comment_db,
      ))
    }
    Post(subreddit_name, username, comment) -> {
      let subreddit_comment_db =
        add_comment(state.subreddit_comment_db, subreddit_name, #(
          username,
          "",
          comment,
        ))

      actor.continue(State(
        state.internal,
        state.stack,
        state.users_db,
        state.subreddit_user_db,
        subreddit_comment_db,
      ))
    }
    Comment(subreddit_name, username, parent_comment, comment) -> {
      let subreddit_comment_db =
        add_comment(state.subreddit_comment_db, subreddit_name, #(
          username,
          parent_comment,
          comment,
        ))

      actor.continue(State(
        state.internal,
        state.stack,
        state.users_db,
        state.subreddit_user_db,
        subreddit_comment_db,
      ))
    }
  }
}

pub fn main() {
  io.println("Hello from project4!")

  let users_db = dict.new()
  let subreddit_user_db = dict.new()
  let subreddit_comment_db = dict.new()

  let assert Ok(engine_actor) =
    actor.new(State(#(0), [], users_db, subreddit_user_db, subreddit_comment_db))
    |> actor.on_message(handle_message)
    |> actor.start
}

/// Add a value to the list stored under a key,
/// or create a new list if the key doesn’t exist.
pub fn add_to_list_in_dict(
  d: dict.Dict(String, List(String)),
  key: String,
  value: String,
) -> dict.Dict(String, List(String)) {
  dict.upsert(d, key, fn(existing: option.Option(List(String))) {
    case existing {
      option.Some(current_list) -> list.append(current_list, [value])
      option.None -> [value]
    }
  })
}

pub fn add_comment(
  d: dict.Dict(String, List(#(String, String, String))),
  key: String,
  value: #(String, String, String),
) -> dict.Dict(String, List(#(String, String, String))) {
  dict.upsert(
    d,
    key,
    fn(existing: option.Option(List(#(String, String, String)))) {
      case existing {
        option.Some(current_list) -> list.append(current_list, [value])
        option.None -> [value]
      }
    },
  )
}

pub fn remove_from_list_in_dict(
  d: dict.Dict(String, List(String)),
  key: String,
  value: String,
) -> dict.Dict(String, List(String)) {
  dict.upsert(d, key, fn(existing) {
    case existing {
      // Key exists → remove the value from the list
      option.Some(xs) -> list.filter(xs, fn(x) { x != value })
      // Key does not exist → nothing, return empty list
      option.None -> []
    }
  })
}
