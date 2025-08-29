import argv
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor

const epsilon = 0.000001

pub type ControlMessage {
  Valid(Int)
  Panic(id: Int, err: String)
}

pub type WorkerMessage {
  Work(Int)
  Kill(reply_to: Subject(Result(Nil, String)))
}

pub type State {
  State(id: Int, pipe: Subject(ControlMessage))
}

fn usage() {
  "usage: ./program <upper_bound>: Int <seq_length>: Int" |> io.println_error
}

pub fn main() {
  case argv.load().arguments {
    [b, l] -> {
      case int.parse(b), int.parse(l) {
        Ok(bound), Ok(length) if length > 0 && bound > 0 ->
          case cli_run(bound, length) {
            Ok(_) -> Nil
            Error(err) -> { "Error: " <> err } |> io.println_error
          }
        _, _ -> usage()
      }
    }
    _ -> usage()
  }
}

fn cli_run(bound: Int, length: Int) -> Result(Nil, String) {
  let assert Ok(aggregator) =
    actor.new(0)
    |> actor.on_message(fn(s, msg) {
      case msg {
        Valid(n) -> int.to_string(n) |> io.println
        Panic(id, err) ->
          { "Worker<" <> int.to_string(id) <> "> panicked: " <> err }
          |> io.println_error
      }
      actor.continue(s)
    })
    |> actor.start

  let workers =
  list.range(1, bound)
    |> list.map(fn(id) { worker_run(id, aggregator.data) })

  workers |> list.each(fn(w) { actor.send(w, Work(length)) })
  workers |> list.each(fn(w) { actor.call(w, 1000, Kill) })

  Ok(Nil)
}

fn worker_run(
  id: Int,
  aggregator: Subject(ControlMessage),
) -> Subject(WorkerMessage) {
  let assert Ok(started) =
    actor.new(State(id, aggregator))
    |> actor.on_message(handle)
    |> actor.start

  started.data
}

fn handle(state: State, msg: WorkerMessage) -> actor.Next(State, WorkerMessage) {
  case msg {
    Work(length) -> {
      case
        {
          {
            sum_of_squares(state.id + length - 1)
            -. sum_of_squares(state.id - 1)
          }
          |> float.square_root
        }
      {
        Ok(value) ->
          case
            float.loosely_equals(
              value,
              int.to_float(float.truncate(value)),
              epsilon,
            )
          {
            True -> actor.send(state.pipe, Valid(state.id))
            False -> Nil
          }
        Error(_) -> actor.send(state.pipe, Panic(state.id, "invalid sequence"))
      }
      actor.continue(state)
    }
    Kill(parent) -> {
      actor.send(parent, Ok(Nil))
      actor.stop()
    }
  }
}

fn sum_of_squares(x: Int) -> Float {
  int.to_float(x * { x + 1 } * { { 2 * x } + 1 }) /. 6.0
}
