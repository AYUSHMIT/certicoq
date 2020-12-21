# CertiCoq

```
<p align="center">
<img src="https://zoep.github.io/certicoq.png" alt="MetaCoq" width="100px"/>
</p>
```

## Overview

CertiCoq is a compiler for Gallina, the specification language of the [Coq proof assistant](https://coq.inria.fr/refman/index.html). CertiCoq targets to Clight, a subset of the C language that can be compiled with any C compiler, including the [CompCert]() verified compiler.

Large parts of the CertiCoq compiler have been verified whereas others are in the process of being verified.

## Documentation

The [CertiCoq Wiki](https://github.com/PrincetonUniversity/certicoq/wiki) has instructions for using the [CertiCoq plugin](https://github.com/PrincetonUniversity/certicoq/wiki/The-CertiCoq-plugin) to compile Gallina to C and use the generated C code.

You can also find some demos [here](https://github.com/PrincetonUniversity/certicoq/blob/master/benchmarks/tests.v) and [here](https://github.com/PrincetonUniversity/certicoq/blob/master/benchmarks/axioms/tests.v).

## Installation Instructions

See [INSTALL.md](https://github.com/PrincetonUniversity/certicoq/INSTALL.md)  for installation instructions.

## Current Members

Andrew Appel, Yannick Forster, Anvay Grover, Joomy Korkut, John Li, Zoe Paraskevopoulou, and Matthieu Sozeau.

## Past Members and Contributors

Abhishek Anand, Greg Morrisett, Randy Pollack, Olivier Savary Belanger, Matthew Weaver

## License 

CertiCoq is open source and distributed unter the [MIT lisence](https://github.com/MetaCoq/metacoq/tree/coq-8.11/LICENSE).


## Directory structure

* `theories/` contains the sources of the compiler
* `plugin/` contains the CertiCoq plugin for Coq 
* `benchmarks/` contains our bechmark suite

Structure of the theories directory:

* `theories/common`: contains common code utilities 
* `theories/Compiler`: contains the toplevel CertiCoq pipeline 
* `theories/L1g`: 1st pass, moves from (MetaCoq's) λbox to our similar L1g
* `theories/L2k_noCnstrParams`: 2nd pass, eta expands constructors and removes constructor parameters 
* `theories/L4_deBruijn`: 3rd pass, let-bind environment
* `theories/L6_PCPS` contains the λANF pipeline (and conversions -- direct and CPS -- to λ_ANF)
* `theories/L7` contains the C code generator.
* `theories/compcert` contains a local copy of the compcert compiler