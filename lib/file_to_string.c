#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>

char *file_to_string(char *path)
{
    char *str;
    int fd;
    off_t size;

    fd = open(path, O_RDONLY);
    if (fd < 0)
        return NULL;
    size = lseek(fd, 0, SEEK_END);
    if (size < 0)
        return (close(fd), NULL);
    lseek(fd, 0, SEEK_SET);
    str = malloc(size + 1);
    if (!str)
        return (close(fd), NULL);
    if (read(fd, str, size) != size)
        return (close(fd), free(str), NULL);
    str[size] = '\0';
    close(fd);
    return str;
}

void my_putstr(char *str)
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