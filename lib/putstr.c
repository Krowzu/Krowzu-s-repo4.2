#include <unistd.h>
#include <stdlib.h>

void my_putstr(const char *str)
{
	int i = 0;
    while (str[i])
        i++;
	write(1, str, i);
}

int main (char *av)
{
    my_putstr(av);
    return 0;
}