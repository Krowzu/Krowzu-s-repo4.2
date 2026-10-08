/*
** EPITECH PROJECT, 2026
** my_compute_power_rec.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_compute_power_rec(int nb, int power)
{
    if (power < 0)
        return 0;
    if (power == 0)
        return 1;
    return nb * my_compute_power_rec(nb, power - 1);
}
