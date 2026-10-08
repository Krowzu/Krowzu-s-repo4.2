/*
** EPITECH PROJECT, 2026
** my_is_prime.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_is_prime(int nb)
{
    int p;

    if (nb < 2)
        return 0;
    for (p = 2; p * p <= nb; p++) {
        if (nb % p == 0)
            return 0;
    }
    return 1;
}
