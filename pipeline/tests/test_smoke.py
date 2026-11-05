"""Smoke test: the locked environment imports every pinned analysis library."""


def test_imports():
    import matplotlib, numpy, pandas, pydantic, scipy, sklearn, statsmodels, yaml  # noqa: F401
