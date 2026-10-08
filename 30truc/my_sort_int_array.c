/*
** EPITECH PROJECT, 2026
** my_sort_int_array.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

void my_sort_int_array(int *tab, int size)
{
    int p = 0;
    int w = 0;

    for (; p < size - 1; p++) {
        for (; w < size - 1 - p; w++) {
            if (tab[w] > tab[w + 1]) {
                int t = tab[w];

                tab[w] = tab[w + 1];
                tab[w + 1] = t;
            }
        }
    }
}
