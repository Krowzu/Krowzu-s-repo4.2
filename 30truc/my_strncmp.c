/*
** EPITECH PROJECT, 2026
** my_strncmp.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_strncmp(char const *s1, char const *s2, int n)
{
    int h = 0;

    if (n <= 0)
        return 0;
    for (; h < n - 1 && s1[h] != '\0' && s1[h] == s2[h]; h++);
    return s1[h] - s2[h];
}
