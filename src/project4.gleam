import gleam/io
import gleam/otp/actor

pub type State {
  State(internal: #(Int), stack: List(String))
}

pub type Message {
  Shutdown
  SetInternal(#(Int))
  RegisterAccount(#(String, String))
  CreateSubReddit(String)
  JoinSubReddit(#(String, String))
  LeaveSubReddit(#(String, String))
  Post(#(String, String, String))
  // Push(String)
  // PopGossip(process.Subject(Result(Int, Nil)))
}

fn handle_message(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    Shutdown -> actor.stop()
    SetInternal(#(v1)) -> {
      actor.continue(State(#(v1), state.stack))
    }
    RegisterAccount(#(username, password)) -> {
      actor.continue(state)
    }
    CreateSubReddit(subreddit_name) -> {
      actor.continue(state)
    }
    JoinSubReddit(#(subreddit_name, username)) -> {
      actor.continue(state)
    }
    LeaveSubReddit(#(subreddit_name, username)) -> {
      actor.continue(state)
    }
    Post(#(subreddit_name, username, comment)) -> {
      actor.continue(state)
    }
  }
}

pub fn main() {
  io.println("Hello from project4!")

  let assert Ok(central_actor) =
    actor.new(State(#(0), []))
    |> actor.on_message(handle_message)
    |> actor.start

  central_actor.data
}
