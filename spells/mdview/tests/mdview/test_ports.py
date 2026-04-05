from lib.registry import choose_port


def test_choose_first_free_port_in_range():
    port = choose_port(17700, 17702, in_use={17700, 17701})
    assert port == 17702
