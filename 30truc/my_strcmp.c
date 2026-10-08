/*
** EPITECH PROJECT, 2026
** my_strcmp.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_strcmp(char const *s1, char const *s2)
{
    int g = 0;

    for (; s1[g] != '\0' && s1[g] == s2[g]; g++);
    return s1[g] - s2[g];
}
