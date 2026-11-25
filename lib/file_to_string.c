#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>

char *file_to_string(char *path)
{
    char *str;
    int b;
    off_t size;
    b = open(path, O_RDONLY);
    if (b < 0)
        return NULL;
    size = lseek(b, 0, SEEK_END);
    if (size < 0)
        return (close(b), NULL);
    lseek(b, 0, SEEK_SET);
    str = malloc(size + 1);
    if (!str)
        return (close(b), NULL);
    if (read(b, str, size) != size)
        return (close(b), free(str), NULL);
    str[size] = '\0';
    close(b);
    return str;
}

void my_putstr(const char *str)
{
	int i = 0;
    while (str[i])
        i++;
	write(1, str, i);
}

int main(int ac, char **av)
{
    char *str;
    if (ac != 2)
        return 1;
    str = file_to_string(av[1]);
    if (!str)
        return 1;
    my_putstr(str);
    free(str);
    return 0;
}