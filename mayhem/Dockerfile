# Build Stage
FROM fuzzers/atheris:2.0.7-python3.9
RUN apt-get update && \
    DEBIAN_FRONTEND=NONINTERACTIVE apt-get install -y clang
ADD . /src
WORKDIR /src
ENV CC='clang'
ENV CXX='clang++'
ENV CFLAGS='-fsanitize=fuzzer-no-link'
ENV CXXFLAGS='-fsanitize=fuzzer-no-link'

RUN python3 -m pip install . --no-binary :all:

ENV LD_PRELOAD="${LD_PRELOAD}:/usr/local/lib/python3.9/dist-packages/ubsan_with_fuzzer.so"
CMD ["/src/mayhem/fuzz_loads_dumps.py"]
