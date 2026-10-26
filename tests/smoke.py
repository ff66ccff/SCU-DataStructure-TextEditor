"""Current CLI integration smoke checks. Python 3, standard library only."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    exe = Path(sys.argv[1] if len(sys.argv) > 1 else "build/editor.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="texteditor-") as directory:
        root = Path(directory)
        source, output = root / "input.txt", root / "output.txt"

        def run(commands="", *options, code=0):
            result = subprocess.run(
                [str(exe), str(source), str(output), *options],
                input=commands.encode("utf-8"), capture_output=True, timeout=15,
            )
            assert result.returncode == code, (result.returncode, result.stdout, result.stderr)
            return result

        assert subprocess.run([str(exe)], capture_output=True, timeout=15).returncode == 2
        run(code=3)
        print("PASS startup errors")

        source.write_bytes(b"A\nB\nC\n")
        run("g 2\ni X\nr XY\ns /X/Z/\nd\nf\n/ C\nr final\nc\nw\nq\n")
        assert output.read_bytes() == b"A\nB\nfinal\n"
        print("PASS navigation, insert, replace, delete, search, save")

        for content, expected in [(b"A\r\nB\rC\n", b"A\nB\nC\n"),
                                  (b"", b""), (b"\n", b"\n"),
                                  (b"A", b"A\n")]:
            source.write_bytes(content)
            run("w\nq\n")
            assert output.read_bytes() == expected
        print("PASS newline normalization and empty document")

        source.write_bytes(b"a" * 100000 + b"\n")
        run("s /aa/b/\nw\nq\n")
        assert output.read_bytes() == b"b" * 50000 + b"\n"
        print("PASS long line and non-overlapping replacement")

        source.write_bytes(b"A\n")
        run("r changed\ne\ny\nw\nq\n")
        assert output.read_bytes() == b"A\n"
        run("r changed\ne\nn\nw\nq\n")
        assert output.read_bytes() == b"changed\n"
        print("PASS reload confirmation and cancellation")

        trace = root / "trace.ndjson"
        run("i extra\nx\nw\nq\n", "--trace", str(trace))
        records = [json.loads(line) for line in trace.read_text(encoding="utf-8").splitlines()]
        assert len(records) >= 3
        assert "extra" in trace.read_text(encoding="utf-8")
        assert output.read_bytes() == b"A\nextra\n"
        print("PASS trace export (JSON decoding and edited content)")
    print("All 6 smoke groups passed.")


if __name__ == "__main__":
    main()
