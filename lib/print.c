#include <unistd.h>

int my_strlen(const char *str)
{
	int i = 0;
	for (; str[i] != '\0'; i++);
	return (i);
}

void my_putstr(const char *str)
{
	if (!str)
		return ;
	write(1, str, my_strlen(str));
}

int	main(int argc, char **argv)
{
	my_putstr(argv[1]);
	return (0);
}
