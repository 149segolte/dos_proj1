import argv
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/result
import pprint

const epsilon = 0.000001

pub type WorkerMessage {
  Work(Int)
  Shutdown
}

pub type State {
  State(id: Int, seq_length: Int)
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

fn cli_run(bound: Int, length: Int) -> Result(_, String) {
  let sv =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.auto_shutdown(supervisor.AllSignificant)

  list.range(1, bound)
  |> list.map(fn(id) {
    supervision.worker(fn() {
      actor.new(State(id, length))
      |> actor.on_message(handle)
      |> actor.start
    })
    |> supervision.significant(True)
  })
  |> list.map(fn(w) {
    w
    |> supervision.map_data(fn(s) {
      actor.send(s, Work(0))
      actor.send(s, Shutdown)
      s
    })
  })
  |> list.each(fn(worker) { supervisor.add(sv, worker) })

  let assert Ok(sv) =
    supervisor.start(sv)
    |> result.map_error(fn(err) {
      "Failed to start supervisor: " <> { err |> pprint.format }
    })

  case process.link(sv.pid) {
    True -> Ok(process.sleep_forever)
    False -> Error("Failed to link to supervisor")
  }
}

fn handle(state: State, msg: WorkerMessage) -> actor.Next(State, WorkerMessage) {
  case msg {
    Work(_) -> {
      case
        {
          sum_of_squares(state.id + state.seq_length - 1)
          -. sum_of_squares(state.id - 1)
        }
        |> float.square_root
        |> result.map(fn(x) {
          float.loosely_equals(x, int.to_float(float.truncate(x)), epsilon)
        })
        |> result.map_error(fn(_) { "Failed to compute square root" })
      {
        Ok(True) -> state.id |> int.to_string |> io.println
        Ok(False) -> Nil
        Error(err) -> { "Error: " <> err } |> io.println_error
      }
      actor.continue(state)
    }
    Shutdown -> actor.stop()
  }
}

fn sum_of_squares(x: Int) -> Float {
  int.to_float(x * { x + 1 } * { { 2 * x } + 1 }) /. 6.0
}
