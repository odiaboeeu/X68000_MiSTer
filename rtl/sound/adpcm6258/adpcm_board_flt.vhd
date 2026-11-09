-- adpcm_board_flt.vhd
-- Filtro analogico da placa CZ-634C/644C (X68000) entre DAOUT do MSM6258 e o mixer:
--   C260/R234/C256 + Sallen-Key IC227 (R233,R232,C255,C254) -> LPF 3a ordem (~3,3 kHz)
--   C232/R261 + C231/R230 (pan)                              -> HPF 2a ordem (~250 Hz)
--   R247//C229 do somador IC227                               -> polo 18,6 kHz
-- Funcao de transferencia obtida por analise nodal (Rda MSM6258 = 17k, faixa 12k-22k),
-- discretizada por bilinear a 125 kHz (40 MHz / 320), 3 biquads DF1, coef. Q2.24.
-- Ganho normalizado: 0 dB em 1 kHz (nivel atual do mixer preservado).
-- Erro vs. modelo analogico: <0,1 dB ate 5 kHz, -0,3 dB em 7,8 kHz.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adpcm_board_flt is
port(
	clk	:in std_logic;		-- 40 MHz (sndclk = clk_sys)
	rstn	:in std_logic;
	din	:in std_logic_vector(11 downto 0);	-- pcm_snd
	dout	:out std_logic_vector(15 downto 0)	-- mesma escala de pcm_snd & "000"
);
end adpcm_board_flt;

architecture rtl of adpcm_board_flt is
	constant DIV	:integer := 320;
	constant CF	:integer := 24;
	type coef_row_t is array(0 to 4) of integer;	-- b0 b1 b2 -a1 -a2
	type coef_t is array(0 to 2) of coef_row_t;
	constant COEF :coef_t := (
		(720654, 1441308, 720654, 18359413, -4422088),
		(130653, 261306, 130653, 29066692, -12809584),
		(17305162, -34610324, 17305162, 33315903, -16538727)
	);
	type st_t is array(0 to 2) of signed(23 downto 0);
	signal x1,x2,y1,y2	:st_t := (others=>(others=>'0'));
	signal cnt	:integer range 0 to DIV-1 := 0;
	signal sec	:integer range 0 to 3 := 3;
	signal step	:integer range 0 to 5 := 0;
	signal v	:signed(23 downto 0) := (others=>'0');
	signal acc	:signed(55 downto 0) := (others=>'0');
	signal outr	:signed(15 downto 0) := (others=>'0');

	function sat24(a:signed(55 downto 0)) return signed is
		variable r :signed(55 downto 0);
	begin
		r := shift_right(a + to_signed(2**(CF-1),56), CF);
		if r > to_signed(2**23-1,56) then return to_signed(2**23-1,24);
		elsif r < to_signed(-2**23,56) then return to_signed(-2**23,24);
		else return resize(r,24); end if;
	end function;
	function sat16(a:signed(23 downto 0)) return signed is
		variable r :signed(23 downto 0);
	begin
		r := shift_right(a,8);
		if r > to_signed(32767,24) then return to_signed(32767,16);
		elsif r < to_signed(-32768,24) then return to_signed(-32768,16);
		else return resize(r,16); end if;
	end function;
begin
	process(clk)
		variable c :signed(26 downto 0);
		variable d :signed(23 downto 0);
		variable y :signed(23 downto 0);
	begin
		if rising_edge(clk) then
			if rstn='0' then
				cnt<=0; sec<=3; step<=0; acc<=(others=>'0'); outr<=(others=>'0');
				x1<=(others=>(others=>'0')); x2<=(others=>(others=>'0'));
				y1<=(others=>(others=>'0')); y2<=(others=>(others=>'0'));
			else
				if cnt=DIV-1 then cnt<=0; else cnt<=cnt+1; end if;
				if cnt=0 then
					v<=shift_left(resize(signed(din),24),11);
					sec<=0; step<=0; acc<=(others=>'0');
				elsif sec<3 then
					if step<5 then
						c := to_signed(COEF(sec)(step),27);
						case step is
							when 0 => d := v;
							when 1 => d := x1(sec);
							when 2 => d := x2(sec);
							when 3 => d := y1(sec);
							when others => d := y2(sec);
						end case;
						acc<=acc + resize(c*d,56);
						step<=step+1;
					else
						y := sat24(acc);
						x2(sec)<=x1(sec); x1(sec)<=v;
						y2(sec)<=y1(sec); y1(sec)<=y;
						v<=y; acc<=(others=>'0'); step<=0;
						if sec=2 then outr<=sat16(y); end if;
						sec<=sec+1;
					end if;
				end if;
			end if;
		end if;
	end process;
	dout<=std_logic_vector(outr);
end rtl;
