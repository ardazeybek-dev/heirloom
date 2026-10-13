//// A tiny, dependency-free argument parser: `--flag`, `--key value`,
//// `--key=value`, short aliases and positional arguments.

import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string

pub type Spec {
  /// A boolean switch.
  Switch(long: String, short: String)
  /// An option that takes a value.
  Valued(long: String, short: String)
}

pub type Parsed {
  Parsed(
    options: Dict(String, String),
    switches: List(String),
    positional: List(String),
  )
}

pub type ArgError {
  UnknownOption(String)
  MissingValue(String)
}

pub fn parse(
  arguments: List(String),
  specs: List(Spec),
) -> Result(Parsed, ArgError) {
  loop(arguments, specs, Parsed(dict.new(), [], []))
  |> result.map(fn(p) { Parsed(..p, positional: list.reverse(p.positional)) })
}

fn find(specs: List(Spec), name: String) -> Result(Spec, Nil) {
  list.find(specs, fn(spec) {
    case spec {
      Switch(long, short) | Valued(long, short) ->
        "--" <> long == name || { short != "" && "-" <> short == name }
    }
  })
}

fn loop(
  arguments: List(String),
  specs: List(Spec),
  acc: Parsed,
) -> Result(Parsed, ArgError) {
  case arguments {
    [] -> Ok(acc)
    ["--", ..rest] ->
      Ok(
        Parsed(
          ..acc,
          positional: list.append(list.reverse(rest), acc.positional),
        ),
      )
    [argument, ..rest] ->
      case string.starts_with(argument, "-") && argument != "-" {
        False ->
          loop(
            rest,
            specs,
            Parsed(..acc, positional: [argument, ..acc.positional]),
          )
        True -> {
          let #(name, inline) = case string.split_once(argument, "=") {
            Ok(#(n, v)) -> #(n, Ok(v))
            Error(Nil) -> #(argument, Error(Nil))
          }
          case find(specs, name), inline, rest {
            Error(Nil), _, _ -> Error(UnknownOption(name))
            Ok(Switch(long, _)), _, _ ->
              loop(rest, specs, Parsed(..acc, switches: [long, ..acc.switches]))
            Ok(Valued(long, _)), Ok(value), _ ->
              loop(
                rest,
                specs,
                Parsed(..acc, options: dict.insert(acc.options, long, value)),
              )
            Ok(Valued(long, _)), Error(Nil), [value, ..more] ->
              loop(
                more,
                specs,
                Parsed(..acc, options: dict.insert(acc.options, long, value)),
              )
            Ok(Valued(long, _)), Error(Nil), [] ->
              Error(MissingValue("--" <> long))
          }
        }
      }
  }
}

pub fn get(parsed: Parsed, name: String) -> Result(String, Nil) {
  dict.get(parsed.options, name)
}

pub fn has(parsed: Parsed, name: String) -> Bool {
  list.contains(parsed.switches, name)
}

pub fn describe(error: ArgError) -> String {
  case error {
    UnknownOption(name) -> "unknown option " <> name
    MissingValue(name) -> name <> " needs a value"
  }
}
