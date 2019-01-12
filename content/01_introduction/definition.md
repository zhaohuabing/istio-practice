# What is machine learning?

Two definitions of machine learning has been offered.

## Arthur Samuel
A field of study that gives computers the ability to learn without being explicitly programmed.

机器学习让计算机具有学习的能力，而并不需要显示地为计算机编写"执行特定任务"的程序。

## Tom Mitchell  
A computer program is said to learn from experience E with respect to some task T and some performance measure P, if its performance on T, as measured by P, improves with experience E.

Example: playing checkers.

T = the task of playing checkers.

E = the experience of playing many games of checkers

P = the probability that the program will win the next game.

一个计算机程序可被认为具有从任务（T）的相关经验（E）中学习的能力：如果程序执行任务（T）的表现（P）能够随着经验（E）的增长而提高。

以一个AI国际象棋程序为例说明：

T：国际象棋比赛

E： 训练程序下棋的次数

P：程序赢得比赛的几率

## 总结思考

## ”传统“程序

直接编写该程序来解决特定的问题。其模式如下：

输入 ---> 程序 -----> 输出

## 机器学习

通过对数据（经验）的学习而生成一个程序，然后通过该程序来解决一类相似的问题。

机器学习也需要通过编程来实现，不同点是机器学习编程面对的抽象层次更高，该程序实现了学习过程，并通过该程序来生成最终解决问题的程序。

1. 机器学习程序 + 训练数据 ----> 解决实际问题的程序 

2. 输入 ---> 解决实际问题的程序 ----> 输出