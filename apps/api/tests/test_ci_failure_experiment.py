"""Deliberately failing test for the G07.8 CI experiment. Not for merge."""


def test_deliberate_failure_blocks_the_pipeline():
    assert 1 + 1 == 3, "Deliberate failure: this pull request shows that a failing test fails CI"
