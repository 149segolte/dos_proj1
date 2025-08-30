import argv
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/result

const epsilon = 0.000001

const max_workers = 6

pub type ControlMessage {
  Outcome(id: Int, task: Int, out: Result(Bool, String))
  Status(reply_to: Subject(Bool), expected: Int)
}

pub type WorkerMessage {
  Work(Int)
  Shutdown
}

pub type State {
  State(id: Int, out_pipe: Subject(ControlMessage), seq_length: Int)
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
  let aggregator = aggregator()

  let workers =
    list.range(1, max_workers)
    |> list.map(fn(id) { worker(State(id, aggregator, length)) })

  workers
  |> list.repeat({ bound / max_workers } + 1)
  |> list.flatten
  |> list.zip(list.range(1, bound))
  |> list.each(fn(ele) { actor.send(ele.0, Work(ele.1)) })

  // Wait for all workers to finish
  workers |> list.each(fn(w) { actor.send(w, Shutdown) })

  case aggregator_close(aggregator, bound) {
    True -> Ok(Nil)
    False -> Error("Failed to close aggregator")
  }
}

fn aggregator() -> Subject(ControlMessage) {
  let assert Ok(aggregator) =
    actor.new(0)
    |> actor.on_message(fn(count, msg) {
      case msg {
        Outcome(id, task, out) -> {
          case out {
            Ok(True) -> int.to_string(task) |> io.println
            Ok(False) -> Nil
            Error(err) ->
              {
                "Worker<"
                <> int.to_string(id)
                <> "> failed task "
                <> int.to_string(task)
                <> ": "
                <> err
              }
              |> io.println_error
          }
          actor.continue(count + 1)
        }
        Status(reply_to, expected) -> {
          let status = expected == count
          actor.send(reply_to, status)
          case status {
            True -> actor.stop()
            False -> actor.continue(count)
          }
        }
      }
    })
    |> actor.start

  aggregator.data
}

fn aggregator_close(pipe: Subject(ControlMessage), expected: Int) -> Bool {
  case process.call_forever(pipe, fn(a) { Status(a, expected) }) {
    True -> True
    False -> aggregator_close(pipe, expected)
  }
}

fn worker(state: State) -> Subject(WorkerMessage) {
  let assert Ok(started) =
    actor.new(state)
    |> actor.on_message(handle)
    |> actor.start

  started.data
}

fn handle(state: State, msg: WorkerMessage) -> actor.Next(State, WorkerMessage) {
  case msg {
    Work(seq_start) -> {
      actor.send(
        state.out_pipe,
        Outcome(
          state.id,
          seq_start,
          {
            sum_of_squares(seq_start + state.seq_length - 1)
            -. sum_of_squares(seq_start - 1)
          }
            |> float.square_root
            |> result.map(fn(x) {
              float.loosely_equals(x, int.to_float(float.truncate(x)), epsilon)
            })
            |> result.map_error(fn(_) { "Failed to compute square root" }),
        ),
      )
      actor.continue(state)
    }
    Shutdown -> actor.stop()
  }
}

fn sum_of_squares(x: Int) -> Float {
  int.to_float(x * { x + 1 } * { { 2 * x } + 1 }) /. 6.0
}
