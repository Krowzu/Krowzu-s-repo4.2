/*
** EPITECH PROJECT, 2026
** my_putchar.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

void my_putchar(char c)
{
    write(1, &c, 1);
}
