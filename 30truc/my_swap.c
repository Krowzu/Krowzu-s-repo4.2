/*
** EPITECH PROJECT, 2026
** my_swap.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

void my_swap(int *a, int *b)
{
    int c = *a;

    *a = *b;
    *b = c;
}
