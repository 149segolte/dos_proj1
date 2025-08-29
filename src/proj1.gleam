import argv
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/result

const epsilon = 0.000001

fn usage() {
  io.println_error("usage: ./program <upper_bound>: Int <seq_length>: Int")
}

pub fn main() {
  // Parse command line arguments
  case argv.load().arguments {
    [b, l] -> {
      case int.parse(b), int.parse(l) {
        Ok(bound), Ok(length) if length > 0 && bound > 0 ->
          case cli_run(bound, length) {
            Ok(_) -> Nil
            Error(err) -> io.println_error("Error: " <> err)
          }
        _, _ -> usage()
      }
    }
    _ -> usage()
  }
}

pub type ControlMessage {
  Valid(Int)
  Panic(String)
}

pub type WorkerMessage {
  Work(Int)
  Kill(reply_to: Subject(Result(Nil, String)))
}

pub type State {
  State(id: Int, pipe: Subject(ControlMessage))
}

fn cli_run(bound: Int, length: Int) -> Result(Nil, String) {
  let assert Ok(accumulator) =
    actor.new(0)
    |> actor.on_message(fn(_, msg) {
      case msg {
        Valid(n) -> io.println(int.to_string(n))
        Panic(err) -> io.println_error("Worker panicked: " <> err)
      }
      actor.continue(0)
    })
    |> actor.start

  echo sum_of_squares(24)
  echo sum_of_squares(6)
  echo { sum_of_squares(24) -. sum_of_squares(6) }

  list.range(1, bound)
  |> list.map(fn(id) { worker_run(id, accumulator.data) })
  |> list.map(fn(w) {
    actor.send(w, Work(length))
    w
  })
  |> list.each(fn(w) { actor.call(w, 1000, Kill) })

  Ok(Nil)
}

fn worker_run(
  id: Int,
  accumulator: Subject(ControlMessage),
) -> Subject(WorkerMessage) {
  let assert Ok(started) =
    actor.new(State(id, accumulator))
    |> actor.on_message(handle)
    |> actor.start

  started.data
}

fn handle(state: State, msg: WorkerMessage) -> actor.Next(State, WorkerMessage) {
  case msg {
    Work(length) -> {
      case
        {
          // list.range(state.id, state.id + length - 1)
          // |> list.map(fn(x) { x * x })
          // |> list.reduce(fn(acc, x) { acc + x })
          // |> result.try(int.square_root)
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
        Error(_) -> actor.send(state.pipe, Panic("error: invalid sequence"))
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
