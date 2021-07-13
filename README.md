# RISCV4Stage
2 difference processors for Riscv

The first is a multi cycle non-pipelined approach, it uses a very unique way to align registers with memory, meaning that it is very easy to extend the cycle length (just change one variable)

The second is a pipelined approach (4 stage pipeline), it is 3.5x faster than the previous, and also uses neet signal processing to make it easy to use

Both use a modular design, and use a cominational control unit (no need for the problems that come with sequential control)

