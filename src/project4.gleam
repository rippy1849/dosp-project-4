import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/string
import gleam/time/timestamp

pub type State {
  State(
    internal: #(Int, Int),
    engine_actor: List(process.Subject(Message)),
    users_db: dict.Dict(String, String),
    subreddit_user_db: dict.Dict(String, List(String)),
    subreddit_comment_db: dict.Dict(
      String,
      List(#(Int, Int, String, Int, String)),
    ),
    user_karma: dict.Dict(String, Int),
    user_dm_db: dict.Dict(String, dict.Dict(String, List(#(String, Int, Int)))),
  )
}

// pub type ClientState{
//   ClientState(

//   )
// }

pub type Message {
  Shutdown
  SetInternal(#(Int, Int))
  RegisterAccount(String, String)
  CreateSubReddit(String)
  JoinSubReddit(String, String)
  LeaveSubReddit(String, String)
  Post(String, String, String)
  Comment(String, String, Int, String)
  UpVote(String, Int)
  DownVote(String, Int)
  EngineDm(String, String, String, Int)
  UserDm(String, String, String)
  DoSomething(process.Subject(Message))
  // Push(String)
  // PopGossip(process.Subject(Result(Int, Nil)))
}

fn handle_message(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    Shutdown -> actor.stop()
    SetInternal(#(v1, v2)) -> {
      actor.continue(State(
        #(v1, v2),
        state.engine_actor,
        state.users_db,
        state.subreddit_user_db,
        state.subreddit_comment_db,
        state.user_karma,
        state.user_dm_db,
      ))
    }
    RegisterAccount(username, password) -> {
      let users_db = dict.insert(state.users_db, username, password)

      actor.continue(State(
        state.internal,
        state.engine_actor,
        users_db,
        state.subreddit_user_db,
        state.subreddit_comment_db,
        state.user_karma,
        state.user_dm_db,
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
        state.engine_actor,
        state.users_db,
        subreddit_user_db,
        state.subreddit_comment_db,
        state.user_karma,
        state.user_dm_db,
      ))
    }
    JoinSubReddit(subreddit_name, username) -> {
      let subreddit_db =
        add_to_list_in_dict(state.subreddit_user_db, subreddit_name, username)

      actor.continue(State(
        state.internal,
        state.engine_actor,
        state.users_db,
        subreddit_db,
        state.subreddit_comment_db,
        state.user_karma,
        state.user_dm_db,
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
        state.engine_actor,
        state.users_db,
        subreddit_db,
        state.subreddit_comment_db,
        state.user_karma,
        state.user_dm_db,
      ))
    }
    Post(subreddit_name, username, comment) -> {
      let #(current_comment_id, current_dm_id) = state.internal
      let current_comment_id = current_comment_id + 1

      let subreddit_comment_db =
        add_comment(state.subreddit_comment_db, subreddit_name, #(
          0,
          current_comment_id,
          username,
          0,
          comment,
        ))

      actor.continue(State(
        #(current_comment_id, current_dm_id),
        state.engine_actor,
        state.users_db,
        state.subreddit_user_db,
        subreddit_comment_db,
        state.user_karma,
        state.user_dm_db,
      ))
    }
    Comment(subreddit_name, username, parent_comment_id, comment) -> {
      let #(current_comment_id, current_dm_id) = state.internal
      let current_comment_id = current_comment_id + 1
      let subreddit_comment_db =
        add_comment(state.subreddit_comment_db, subreddit_name, #(
          0,
          current_comment_id,
          username,
          parent_comment_id,
          comment,
        ))

      actor.continue(State(
        #(current_comment_id, current_dm_id),
        state.engine_actor,
        state.users_db,
        state.subreddit_user_db,
        subreddit_comment_db,
        state.user_karma,
        state.user_dm_db,
      ))
    }
    UpVote(subreddit_name, post_comment_id) -> {
      let result = dict.get(state.subreddit_comment_db, subreddit_name)

      let comments = case result {
        Ok(result) -> result
        Error(_) -> []
      }

      let #(
        updown,
        comment_id,
        post_username,
        post_parent_comment_id,
        comment_contents,
      ) = find_comment(comments, post_comment_id)

      // echo comment_id

      let new_comment_list = delete_comment(comments, comment_id)

      // echo new_comment_list

      let updown = updown + 1

      let new_karma = update_karma_up(state.user_karma, post_username)

      let updated_comment = #(
        updown,
        comment_id,
        post_username,
        post_parent_comment_id,
        comment_contents,
      )

      let new_comment_list = list.append(new_comment_list, [updated_comment])

      let subreddit_comment_db =
        update_comment_dict(
          state.subreddit_comment_db,
          subreddit_name,
          new_comment_list,
        )

      // echo subreddit_comment_db
      // echo new_karma

      actor.continue(State(
        state.internal,
        state.engine_actor,
        state.users_db,
        state.subreddit_user_db,
        subreddit_comment_db,
        new_karma,
        state.user_dm_db,
      ))
    }

    DownVote(subreddit_name, post_comment_id) -> {
      let result = dict.get(state.subreddit_comment_db, subreddit_name)

      let comments = case result {
        Ok(result) -> result
        Error(_) -> []
      }

      let #(
        updown,
        comment_id,
        post_username,
        post_parent_comment_id,
        comment_contents,
      ) = find_comment(comments, post_comment_id)

      // echo comment_id

      let new_comment_list = delete_comment(comments, comment_id)

      // echo new_comment_list

      let updown = updown - 1

      let new_karma = update_karma_down(state.user_karma, post_username)

      let updated_comment = #(
        updown,
        comment_id,
        post_username,
        post_parent_comment_id,
        comment_contents,
      )

      let new_comment_list = list.append(new_comment_list, [updated_comment])

      let subreddit_comment_db =
        update_comment_dict(
          state.subreddit_comment_db,
          subreddit_name,
          new_comment_list,
        )

      // echo subreddit_comment_db

      actor.continue(State(
        state.internal,
        state.engine_actor,
        state.users_db,
        state.subreddit_user_db,
        subreddit_comment_db,
        new_karma,
        state.user_dm_db,
      ))
    }
    EngineDm(from_username, to_username, content, parent_comment_id) -> {
      let #(current_comment_id, current_dm_id) = state.internal

      let current_dm_id = current_dm_id + 1

      let user_dm_db =
        add_dm(
          from_username,
          to_username,
          content,
          current_dm_id,
          parent_comment_id,
          state.user_dm_db,
        )

      let user_dm_db =
        add_dm(
          to_username,
          from_username,
          content,
          current_dm_id,
          parent_comment_id,
          user_dm_db,
        )
      // echo user_dm_db

      actor.continue(State(
        #(current_comment_id, current_dm_id),
        state.engine_actor,
        state.users_db,
        state.subreddit_user_db,
        state.subreddit_comment_db,
        state.user_karma,
        user_dm_db,
      ))
    }
    UserDm(from_username, to_username, content) -> {
      actor.continue(State(
        state.internal,
        state.engine_actor,
        state.users_db,
        state.subreddit_user_db,
        state.subreddit_comment_db,
        state.user_karma,
        state.user_dm_db,
      ))
    }
    DoSomething(client) -> {
      let rand = int.random(4)

      let random_string = random_string(10)

      case rand {
        0 -> {
          process.send(
            client,
            Post(random_string, random_string, random_string),
          )
        }
        1 -> {
          process.send(
            client,
            Comment(random_string, random_string, 1, random_string),
          )
        }
        2 -> {
          process.send(client, JoinSubReddit(random_string, random_string))
        }
        _ -> Nil
      }

      actor.continue(state)
    }
  }
}

pub fn main() {
  io.println("Hello from Rippy!")

  let user_db = dict.new()
  let subreddit_user_db = dict.new()
  let subreddit_comment_db = dict.new()
  let user_karma_db = dict.new()
  let user_dm_db = dict.new()

  let assert Ok(engine_actor) =
    actor.new(State(
      #(0, 0),
      [],
      user_db,
      subreddit_user_db,
      subreddit_comment_db,
      user_karma_db,
      user_dm_db,
    ))
    |> actor.on_message(handle_message)
    |> actor.start

  let engine_handle = engine_actor.data

  process.send(engine_handle, RegisterAccount("Griz", "test"))
  process.send(engine_handle, CreateSubReddit("Raves"))
  process.send(engine_handle, JoinSubReddit("Lsdream", "Raves"))
  process.send(engine_handle, Post("Raves", "Griz", "Raves are cool"))
  process.send(engine_handle, Comment("Raves", "Lsdream", 1, "I agree"))

  //Upvoting comment with id 1
  process.send(engine_handle, UpVote("Raves", 1))
  process.send(engine_handle, EngineDm("Griz", "Lsdream", "Hey", 0))
  process.send(engine_handle, EngineDm("Griz", "Lsdream", "What's up?", 0))

  let number_list = list.range(0, 2)

  // echo number_list

  let actor_list =
    list.map(number_list, fn(n) {
      let assert Ok(started) =
        actor.new(State(
          #(0, 0),
          [engine_handle],
          user_db,
          subreddit_user_db,
          subreddit_comment_db,
          user_karma_db,
          user_dm_db,
        ))
        |> actor.on_message(handle_message)
        |> actor.start

      started.data
    })

  do_something(actor_list, engine_handle)

  process.sleep(1000)
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
  d: dict.Dict(String, List(#(Int, Int, String, Int, String))),
  key: String,
  value: #(Int, Int, String, Int, String),
) -> dict.Dict(String, List(#(Int, Int, String, Int, String))) {
  dict.upsert(
    d,
    key,
    fn(existing: option.Option(List(#(Int, Int, String, Int, String)))) {
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

pub fn find_comment(
  xs: List(#(Int, Int, String, Int, String)),
  b: Int,
) -> #(Int, Int, String, Int, String) {
  let matches =
    list.filter(xs, fn(tuple) {
      case tuple {
        #(i, i2, s1, i3, s3) -> i2 == b
      }
    })

  case matches {
    [] -> #(0, 0, "", 0, "")
    // default tuple if not found
    [first, ..] -> first
  }
}

pub fn delete_comment(
  xs: List(#(Int, Int, String, Int, String)),
  b: Int,
) -> List(#(Int, Int, String, Int, String)) {
  list.filter(xs, fn(tuple) {
    case tuple {
      #(i, i2, s1, i3, s3) -> i2 != b
    }
  })
}

pub fn update_comment_dict(
  d: dict.Dict(String, List(#(Int, Int, String, Int, String))),
  key: String,
  new_list: List(#(Int, Int, String, Int, String)),
) -> dict.Dict(String, List(#(Int, Int, String, Int, String))) {
  dict.insert(d, key, new_list)
}

pub fn update_karma_up(
  a: dict.Dict(String, Int),
  b: String,
) -> dict.Dict(String, Int) {
  dict.upsert(a, b, fn(existing) {
    case existing {
      option.Some(value) -> value + 1
      option.None -> 1
    }
  })
}

pub fn update_karma_down(
  a: dict.Dict(String, Int),
  b: String,
) -> dict.Dict(String, Int) {
  dict.upsert(a, b, fn(existing) {
    case existing {
      option.Some(value) -> value - 1
      option.None -> -1
    }
  })
}

pub fn add_dm(
  a: String,
  b: String,
  c: String,
  e: Int,
  f: Int,
  d: dict.Dict(String, dict.Dict(String, List(#(String, Int, Int)))),
) -> dict.Dict(String, dict.Dict(String, List(#(String, Int, Int)))) {
  dict.upsert(d, a, fn(maybe_inner) {
    // If outer dict (key a) exists, use it, else start new inner dict
    let inner = case maybe_inner {
      option.Some(existing_inner) -> existing_inner
      option.None -> dict.new()
    }

    // Update the inner dict at key b
    let updated_inner =
      dict.upsert(inner, b, fn(maybe_list) {
        case maybe_list {
          option.Some(existing_list) -> list.append(existing_list, [#(c, e, 0)])
          option.None -> [#(c, e, f)]
        }
      })

    updated_inner
  })
}

pub fn do_something(actor_list, engine_handle) {
  let time = timestamp.system_time()
  let time = timestamp.to_unix_seconds(time)
  let time = float_to_int(time)
  let time = time % 60

  // let disconnect_random = int.random(10)
  // echo disconnect_random
  // process.sleep(1000)
  // echo time

  let wait = case time >= 20 && time <= 30 {
    True -> 250
    False -> 1000
  }
  process.sleep(wait)

  list.each(actor_list, fn(actor) {
    process.send(actor, DoSomething(engine_handle))
  })
  do_something(actor_list, engine_handle)
}

@external(erlang, "erlang", "trunc")
pub fn float_to_int(x: Float) -> Int

pub fn random_string(length: Int) -> String {
  // Generate random bytes
  let bytes = crypto.strong_random_bytes(length)

  // Encode as base16 (hex) to make it readable
  let hex = bit_array.base16_encode(bytes)

  // Truncate to desired length (since hex doubles the length)
  let output = string.slice(hex, 0, length)
  output
}
