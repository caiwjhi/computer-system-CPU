------------------------- OP 表 --------------------------
--	0	00001					NOP
--	1	00010					B
--	2	00100					BEQZ
--	3	00101					BNEZ
--	4	00110				00	SLL
--	5	00110				11	SRA
--	6	01000					ADDIU3
--	7	01001					ADDIU
--	8	01100	000				BTEQZ
--	9	01100	011				ADDSP
--	10	01100	100				MTSP
--	11	01101					LI
--	12 	01110					CMPI
--  13  01111                   MOVE
--	14	10010					LW_SP
--	15	10011					LW
--	16	11010					SW_SP
--	17	11011					SW
--	18	11100				01	ADDU
--	19	11100				11	SUBU
--	20	11101		000	000	00	JR
--	21	11101		010	000	00	MFPC
--	22	11101			001	00	SLLV
--	23	11101			011	00	AND
--	24	11101			011	01	OR
--	25	11101			010	10	CMP
--	26	11101			001	11	SRAV	
--	27	11110				00	MFIH
--	28	11110				01	MTIH
--	29	11101  			000	11	SLTU
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

entity cpu is
	port (
		clk_50				: in std_logic;
		clk_1 				: in std_logic;

		L					: out std_logic_vector(15 downto 0) := "0000000000000000";
		
		data_ram1 			: inout  STD_LOGIC_VECTOR (15 downto 0) := "0000000000000000";
		addr_ram1 			: out  STD_LOGIC_VECTOR (17 downto 0) := "000000000000000000";
		OE_ram1 			: out  STD_LOGIC := '1';
		WE_ram1 			: out  STD_LOGIC := '1';
		EN_ram1 			: out  STD_LOGIC := '0';
		

		rdn			: out STD_LOGIC := '1';
		wrn			: out STD_LOGIC := '1';
		data_ready		: in std_logic;
		tbre			: in std_logic;
		tsre			: in std_logic
	);
end cpu;


architecture behavioral of cpu is

	subtype vector	is std_logic_vector(15 downto 0);                            --用于扩展立即数返回
	
	signal do               :std_logic := '0';
	
	--	寄存器
	signal r0				: std_logic_vector(15 downto 0) := "0000000000000000";
	signal r1				: std_logic_vector(15 downto 0) := "0000000000000001";
	signal r2				: std_logic_vector(15 downto 0) := "1000011111111111";
	signal r3				: std_logic_vector(15 downto 0) := "0000000011111111";
	signal r4				: std_logic_vector(15 downto 0) := "0000000000000011";
	signal r5				: std_logic_vector(15 downto 0) := "0000000000000000";
	signal r6				: std_logic_vector(15 downto 0) := "0000000000000000";
	signal r7				: std_logic_vector(15 downto 0) := "0000000000000000";
	-- 专用寄存器
	signal T				: std_logic_vector(15 downto 0) := "0000000000000000";
	signal SP				: std_logic_vector(15 downto 0) := "0000000000011100";
	signal IH				: std_logic_vector(15 downto 0) := "1010101010101010";
	
	--得到寄存器的值
	procedure get_regbin( addr : std_logic_vector( 3 downto 0); signal data : out std_logic_vector( 15 downto 0) ) is
	begin
		case addr is
			when "0000" => data <= r0;
			when "0001" => data <= r1;
			when "0010" => data <= r2;
			when "0011" => data <= r3;
			when "0100" => data <= r4;
			when "0101" => data <= r5;
			when "0110" => data <= r6;
			when "0111" => data <= r7;
			when "1101" => data <= T;
			when "1110" => data <= SP;
			when "1111" => data <= IH;
			when others => data <= "0000000000000000";
		end case;
	end procedure;
	
	-- 符号扩展
	function sign_extend5( imm : std_logic_vector(4 downto 0) ) return vector is
	begin
		if imm(4) = '1' then
			return "11111111111" & imm;
		else
			return "00000000000" & imm;
		end if;
	end function;
	
	
	function sign_extend8( imm : std_logic_vector(7 downto 0) ) return vector is
	begin
		if imm(7) = '1' then
			return "11111111" & imm;
		else
			return "00000000" & imm;
		end if;
	end function;
	
	function sign_extend11( imm : std_logic_vector(10 downto 0) ) return vector is
	begin
		if imm(10) = '1' then
			return "11111" & imm;
		else
			return "00000" & imm;
		end if;
	end function;
	
	signal predict               :std_logic := '0';
	--PRE
	signal pre_pc			: std_logic_vector( 15 downto 0) := "0000000000000000";
	signal pre_pc_from_id	: std_logic_vector( 15 downto 0) := "0000000000000000";   --JR跳转得到 pc
	signal pre_pc_from_exe	: std_logic_vector( 15 downto 0) := "0000000000000000";   --B型跳转后pc
	signal pre_pc_by_id		: std_logic := '0';	                                      --判断是否JR
	signal pre_pc_by_exe	: std_logic := '0';                                       --判断是否B跳

	--IF
	shared variable if_cnt	: integer range 0 to 7 := 0;                               --状态计数
	shared variable if_ins	: std_logic_vector( 15 downto 0) := "0000000000000000";    --指令instrument
	shared variable if_pc	: std_logic_vector( 15 downto 0) := "0000000000000000";    --下次指令的pc
	
	--IF/ID 
	signal if_id_ins		: std_logic_vector( 15 downto 0) := "0000000000000000";
	signal if_id_op			: integer range 0 to 31 := 0;                              --指令进行编号，方便接下来处理
	signal if_id_op_nop_id	: std_logic := '0';                                        --是否插NOP，用于JR跳转
	signal if_id_op_nop_exe	: std_logic := '0';                                        --是否插NOP，用于B型跳转与LA数据冲突
	signal if_id_pc			: std_logic_vector( 15 downto 0) := "0000000000000000";
	
	--ID
	shared variable id_cnt	: integer range 0 to 7 := 0;
	shared variable id_ins	: std_logic_vector( 15 downto 0) := "0000000000000000";
	shared variable id_op	: integer range 0 to 31 := 0;
	shared variable id_pc	: std_logic_vector( 15 downto 0) := "0000000000000000";
	shared variable id_rx	: std_logic_vector( 3 downto 0) := "0000";                 --指令中操作寄存器rx, 用于判断是否数据冲突
	shared variable id_ry	: std_logic_vector( 3 downto 0) := "0000";                 --指令操作寄存器ry，同上
	
	--ID/exe
	signal id_exe_a_exe			: std_logic := '0';
	signal id_exe_a_me			: std_logic := '0';
	signal id_exe_a_from_exe	: std_logic_vector( 15 downto 0) := "0000000000000000";    --从数据旁路得到的rx的值，用于 AA冲突
	signal id_exe_a				: std_logic_vector( 15 downto 0) := "0000000000000000";    --从ID得到的操作寄存器rx的值
	signal id_exe_a_from_me		: std_logic_vector( 15 downto 0) := "0000000000000000";    --从数据旁路得到的rx的值，用于 LA冲突
	signal id_exe_b_exe			: std_logic := '0';
	signal id_exe_b_me			: std_logic := '0';
	signal id_exe_b_from_exe	: std_logic_vector( 15 downto 0) := "0000000000000000";
	signal id_exe_b				: std_logic_vector( 15 downto 0) := "0000000000000000";
	signal id_exe_b_from_me		: std_logic_vector( 15 downto 0) := "0000000000000000";
	signal id_exe_imm			: std_logic_vector( 15 downto 0) := "0000000000000000";    --扩展后的立即数
	signal id_exe_wb			: std_logic := '0';                                        --是否需要写回
	signal id_exe_op			: integer range 0 to 31 := 0;
	signal id_exe_op_nop_exe	: std_logic := '0';                                        --是否插NOP，用于B型跳转与LA数据冲突
	signal id_exe_pc			: std_logic_vector( 15 downto 0) := "0000000000000000";
	signal id_exe_rz			: std_logic_vector( 3 downto 0) := "0000";                 --结果寄存器
	
	--EXE
	shared variable exe_cnt		: integer range 0 to 7 := 0;
	shared variable exe_a		: std_logic_vector( 15 downto 0) := "0000000000000000";
	shared variable exe_b		: std_logic_vector( 15 downto 0) := "0000000000000000";
	shared variable exe_ans		: std_logic_vector( 15 downto 0) := "0000000000000000";
	shared variable exe_addr	: std_logic_vector( 15 downto 0) := "0000000000000000";
	shared variable exe_imm		: std_logic_vector( 15 downto 0) := "0000000000000000";
	shared variable exe_lw 		: std_logic := '0';
	shared variable exe_wb 		: std_logic := '0';
	shared variable exe_br 		: std_logic := '0';                                         --是否跳转
	shared variable exe_pc2		: std_logic_vector( 15 downto 0) := "0000000000000000";     --B跳的新PC地址
	shared variable exe_op		: integer range 0 to 31 := 0;
	shared variable exe_pc		: std_logic_vector( 15 downto 0) := "0000000000000000";
	shared variable exe_rz		: std_logic_vector( 3 downto 0) := "0000";
	
	--EXE/ME
	signal exe_me_wb			: std_logic := '0';
	signal exe_me_op			: integer range 0 to 31 := 0;
	signal exe_me_rz			: std_logic_vector( 3 downto 0) := "0000";
	signal exe_me_ans			: std_logic_vector( 15 downto 0) := "0000000000000000"; 
	signal exe_me_addr			: std_logic_vector( 15 downto 0) := "0000000000000000"; 
	
	--ME 
	shared variable me_cnt		: integer range 0 to 7 := 0;
	shared variable me_data		: std_logic_vector( 15 downto 0) := "0000000000000000";
	shared variable me_wb 		: std_logic := '0';
	shared variable me_op		: integer range 0 to 31 := 0;
	shared variable me_rz		: std_logic_vector( 3 downto 0) := "0000";
	shared variable me_mode		: integer range 0 to 7 := 0;
	
	--ME/WB
	signal me_wb_data		: std_logic_vector( 15 downto 0) := "0000000000000000";
	signal me_wb_wb			: std_logic := '0';
	signal me_wb_rz			: std_logic_vector( 3 downto 0) := "0000";
	signal me_wb_op         : integer range 0 to 31 := 0;
	
	--WB
	shared variable wb_cnt	: integer range 0 to 7 := 0;
	
	--	clock
	signal clk				:	std_logic := '1'; -- actually running clock          

 
	signal	int_r0          : std_logic_vector( 15 downto 0) := "0000000000000000";
	signal  int_r1          : std_logic_vector( 15 downto 0) := "0000000000000000";
	signal  int_imm         : std_logic_vector( 15 downto 0) := "0000000000000000";
	signal  int_pc          : std_logic_vector( 15 downto 0) := "0000000000000000";
	signal  int_jr          : std_logic := '0';
	signal  int_recover     : std_logic := '0';

begin
	
	--IF
	process (clk)
	begin
		if (clk'event and clk = '1') then
			case if_cnt is
				when 0 =>
					
				when 1 =>
					
				when 2 =>
				when 3 =>
				when 4 =>
					pre_pc <= if_pc + "1";
					if_id_pc <= if_pc + "1";
					if_id_ins <= if_ins;
					
					case if_ins(15 downto 11) is    --对指令编号，结果存于OP
						when "00001" =>    -- NOP
							if_id_op <= 0;
						when "00010" =>    -- B
							if_id_op <= 1;
						when "00100" =>    -- BEQZ
							if_id_op <= 2;
						when "00101" =>    -- BNEZ
							if_id_op <= 3;
						when "00110" =>
							if if_ins(1 downto 0) = "00" then      -- SLL
								if_id_op <= 4;
							elsif if_ins(1 downto 0) = "11" then   -- SRA
								if_id_op <= 5;
							end if;
						when "01000" =>    ---  ADDIU3
							if_id_op <= 6;
						when "01001" =>    --   ADDIU
							if_id_op <= 7;
						when "01100" =>
							if if_ins(10 downto 8) = "000" then     --	BTEQZ
								if_id_op <= 8;
							elsif if_ins(10 downto 8) = "011" then  --  ADDSP
								if_id_op <= 9;
							elsif if_ins(10 downto 8) = "100" then  --	MTSP
								if_id_op <= 10;
							end if;
						when "01101" =>    -- LI
							if_id_op <= 11;
						when "01110" =>    -- CMPI
							if_id_op <= 12;
						when "01111" =>          --MOVE
							if_id_op <= 13;	
						when "10010" =>    --LW_SP
							if_id_op <= 14;
						when "10011" =>    -- LW
							if_id_op <= 15;
						when "11010" =>    -- SW_SP
							if_id_op <= 16;
						when "11011" =>    -- SW
							if_id_op <= 17;
						when "11100" =>
							if if_ins(1 downto 0) = "01" then        --	ADDU
								if_id_op <= 18;
							elsif if_ins(1 downto 0) = "11" then     --	SUBU
								if_id_op <= 19;
							end if;
						when "11101" =>
							if if_ins(7 downto 0) = "00000000" then   -- JR
								if_id_op <= 20;
							elsif if_ins(7 downto 0) = "01000000" then  --	MFPC
								if_id_op <= 21;
							else
								case if_ins(4 downto 0) is
									when "00100" => if_id_op <= 22;--  	SLLV
									when "01100" => if_id_op <= 23;--  	AND
									when "01101" => if_id_op <= 24;--  	OR
									when "01010" => if_id_op <= 25;--  	CMP
									when "00111" => if_id_op <= 26;--  	SRAV 
									when "00011" => if_id_op <= 29;--	SLTU
									when others => if_id_op <= 0; -- NOT REACH
								end case;							
							end if;
						when "11110" =>
							if if_ins(1 downto 0) = "00" then     --MFIH
								if_id_op <= 27;
							elsif if_ins(1 downto 0) = "01" then  --MTIH
								if_id_op <= 28;
							end if;
						when "11111" =>
							if_id_op <= 30;
							pre_pc <= "0000000000000101";
						when others =>    
					end case;
				when others =>
			end case;
			if if_cnt = 4 then
				if_cnt := 0;
			else
				if_cnt := if_cnt + 1;
			end if;
		end if;
	end process;
	
	--ID
	process (clk)
	begin
		if clk'event and clk = '1' then
			case id_cnt is
				when 0 =>	
					if if_id_op_nop_exe = '1' or if_id_op_nop_id = '1' then
						id_op := 0;
					else
						id_op := if_id_op;
					end if;
					id_pc := if_id_pc;
					id_ins := if_id_ins;
					id_rx := "1000"; 
					id_ry := "1000";
					
					int_recover <= '0';
				when 1 =>
				when 2 =>
				when 3 =>
					pre_pc_by_id <= '0';
					if_id_op_nop_id <= '0';
					id_exe_pc <= id_pc;
					id_exe_op <= id_op;
					case id_op is
						when 0 =>    --	NOP
						when 1 =>    -- B
							id_exe_wb <= '0';
							
							pre_pc_by_id <= '1';
							pre_pc_from_id <= id_pc +sign_extend11( id_ins(10 downto 0));
						when 2 | 3 =>    --	BEQZ
							id_exe_wb <= '0';
							id_rx := "0" & id_ins(10 downto 8);
							get_regbin( id_rx, id_exe_a );
							id_exe_imm <= sign_extend8( id_ins(7 downto 0) );
							
							if predict = '1' then 
								pre_pc_by_id <= '1';
								pre_pc_from_id <= id_pc +sign_extend8( id_ins(7 downto 0) );
								
							end if;
						when 4 | 5 =>    --	SLL
							id_exe_wb <= '1';
							id_ry := "0" & id_ins( 7 downto 5);
							get_regbin( id_ry, id_exe_b );
							id_exe_imm <= "0000000000000" & id_ins(4 downto 2);
							id_exe_rz <= "0" & id_ins(10 downto 8);
						
						when 6 =>    --   ADDIU3
							id_exe_wb <= '1';
							id_rx := "0" & id_ins(10 downto 8);
							get_regbin( id_rx, id_exe_a);
							id_exe_rz <= "0" & id_ins(7 downto 5);
							id_exe_imm <= sign_extend5( id_ins(3) & id_ins(3 downto 0));
						when 7 =>	    --   ADDIU
							id_exe_wb <= '1';
							id_rx := "0" & id_ins(10 downto 8);
							get_regbin( id_rx, id_exe_a);
							id_exe_rz <= "0" & id_ins(10 downto 8);
							id_exe_imm <= sign_extend8( id_ins(7 downto 0));
						when 8 =>    --   BTEQZ
							id_exe_wb <= '0';
							id_rx := "1101";
							get_regbin( id_rx, id_exe_a );
							id_exe_imm <= sign_extend8( id_ins(7 downto 0) );
							if predict = '1' then 
								pre_pc_by_id <= '1';
								pre_pc_from_id <= id_pc +sign_extend8( id_ins(7 downto 0) );
								
							end if;
						when 9 =>    --	ADDSP
							id_exe_wb <= '1';
							id_rx := "1110";
							get_regbin( id_rx, id_exe_a );
							id_exe_rz <= "1110";
							id_exe_imm <= sign_extend8( id_ins(7 downto 0) );
						when 10 =>    --	MTSP
							id_exe_wb <= '1';
							id_rx := "0" &  id_ins(7 downto 5);
							get_regbin( id_rx, id_exe_a);
							id_exe_rz <= "1110";
						when 11 =>    --   LI
							id_exe_wb <= '1';
							id_exe_rz <= "0" & id_ins(10 downto 8);
							id_exe_imm <= "00000000" & id_ins(7 downto 0);
						when 12 =>    -- 	CMPI
							id_exe_wb <= '1';
							id_rx := "0" & id_ins(10 downto 8);
							get_regbin( id_rx, id_exe_a );
							id_exe_imm <= sign_extend8(id_ins(7 downto 0));
							id_exe_rz <= "1101";
						when 13 =>    --MOVE
							id_exe_wb <= '1';
							id_rx := "0" & id_ins(7 downto 5);
							get_regbin( id_rx, id_exe_a );
							id_exe_rz <="0" & id_ins(10 downto 8);
						when 14 =>    --	LW_SP
							id_exe_wb <= '1';
							id_rx := "1110";
							get_regbin( id_rx, id_exe_a );
							id_exe_rz <= "0" & id_ins(10 downto 8);
							id_exe_imm <= sign_extend8( id_ins(7 downto 0) );
						when 15 =>    --	LW
							id_exe_wb <= '1';
							id_rx := "0" & id_ins(10 downto 8);
							get_regbin( id_rx, id_exe_a );
							id_exe_rz <= "0" & id_ins(7 downto 5);
							id_exe_imm <= sign_extend5( id_ins(4 downto 0) );
						when 16 =>    -- SW_SP
							id_exe_wb <= '0';
							id_rx := "1110";
							get_regbin( id_rx, id_exe_a );
							id_ry := "0" & id_ins(10 downto 8);
							get_regbin( id_ry, id_exe_b );
							id_exe_imm <= sign_extend8( id_ins(7 downto 0) );
						when 17 =>    --	SW
							id_exe_wb <= '0';
							id_rx := "0" & id_ins(10 downto 8);
							get_regbin( id_rx, id_exe_a );
							id_ry := "0" & id_ins(7 downto 5);
							get_regbin( id_ry, id_exe_b );
							id_exe_imm <= sign_extend5( id_ins(4 downto 0) );    --L <= id_rx;
						when 18 | 19 =>    --	ADDU
							id_exe_wb <= '1';
							id_rx := "0" & id_ins(10 downto 8);
							id_ry := "0" & id_ins( 7 downto 5);
							get_regbin( id_rx, id_exe_a );
							get_regbin( id_ry, id_exe_b );
							id_exe_rz <= "0" & id_ins(4 downto 2);
						when 20 =>    --	JR
							id_exe_wb <= '0';
							pre_pc_by_id <= '1';
							get_regbin( "0" & id_ins(10 downto 8), pre_pc_from_id);
							if_id_op_nop_id <= '1';
							if id_ins(10 downto 8)= "110" and int_jr ='1'   then
								int_jr <= '0';
								int_recover <= '1';
							end if;
						when 21 =>    --	MFPC
							id_exe_wb <= '1';
							id_exe_rz <= "0" & id_ins(10 downto 8);
						when 22 | 26=>    --	SLLV
							id_exe_wb <= '1';
							id_rx := "0" & id_ins(10 downto 8);
							get_regbin( id_rx, id_exe_a );
							id_ry := "0" & id_ins(7 downto 5);
							get_regbin( id_ry, id_exe_b );
							id_exe_rz <= "0" & id_ins(7 downto 5);
						when 23 | 24=>    --   AND
							id_exe_wb <= '1';
							id_rx := "0" & id_ins(10 downto 8);
							id_ry := "0" & id_ins( 7 downto 5);
							get_regbin( id_rx, id_exe_a );
							get_regbin( id_ry, id_exe_b );
							id_exe_rz <= "0" & id_ins(10 downto 8);
						when 25 =>    --	CMP
							id_exe_wb <= '1';
							id_rx := "0" & id_ins(10 downto 8);
							id_ry := "0" & id_ins( 7 downto 5);
							get_regbin( id_rx, id_exe_a );
							get_regbin( id_ry, id_exe_b );
							id_exe_rz <= "1101";
						when 27 =>    --	MFIH
							id_exe_wb <= '1';
							id_rx := "1111";
							get_regbin( id_rx, id_exe_a );
							id_exe_rz <= "0" & id_ins(10 downto 8);
						when 28 =>    --	MTIH
							id_exe_wb <= '1';
							id_rx := "0" &  id_ins(10 downto 8);
							get_regbin( id_rx, id_exe_a);
							id_exe_rz <= "1111";
						when 29 =>    --	SLTU
							id_exe_wb <= '1';
							id_rx := "0" & id_ins(10 downto 8);
							id_ry := "0" & id_ins( 7 downto 5);
							get_regbin( id_rx, id_exe_a );
							get_regbin( id_ry, id_exe_b );
							id_exe_rz <= "1101";
						when 30 =>
							id_exe_wb <= '0';
							int_jr <='1';
							int_imm <= "000000000000" & id_ins(3 downto 0);
							int_pc<= id_pc;
						when others =>    --	do nothing
						
					end case;
				when 4 =>
				when others =>
			end case;
			if id_cnt = 4 then
				id_cnt := 0;
			else
				id_cnt := id_cnt + 1;
			end if;
		end if;
	end process;
	
	--EXE
	process (clk)
		variable a : integer;
	begin
		if clk'event and clk = '1' then
			case exe_cnt is		
				when 0 =>
					if id_exe_op_nop_exe = '1' then
						exe_op := 0;
					else
						exe_op := id_exe_op;
					end if;
					if id_exe_a_exe = '1' then
						exe_a := id_exe_a_from_exe;
					elsif id_exe_a_me = '1' then
						exe_a := id_exe_a_from_me;
					else
						exe_a := id_exe_a;
					end if;
					if id_exe_b_exe = '1' then
						exe_b := id_exe_b_from_exe;
					elsif id_exe_b_me = '1' then
						exe_b := id_exe_b_from_me;
					else
						exe_b := id_exe_b;
					end if;
					exe_wb := id_exe_wb;
					exe_pc := id_exe_pc;
					exe_rz := id_exe_rz;
					exe_imm := id_exe_imm;
					exe_lw := '0';
					exe_br := '0';
				when 1 =>
					case exe_op is
						when 0 =>    --	NOP
						when 2 | 8 =>    --	BEQZ	
							if (exe_a = "0000000000000000" and predict = '0' ) or (exe_a /= "0000000000000000" and predict = '1') then
								exe_br := '1';
								exe_pc2 := exe_pc + exe_imm;
							end if;
						when 3 =>    --   BNEZ 
							if (exe_a /= "0000000000000000" and predict = '0') or (exe_a = "0000000000000000" and predict = '1' ) then
								exe_br := '1';
								exe_pc2 := exe_pc + exe_imm;
							end if;
						when 4 =>    ---	SLL
							if exe_imm = "0000000000000000" then
								a := 8;
							else 
								a := conv_integer(exe_imm);
							end if;
							exe_ans := to_stdlogicvector(to_bitvector(exe_b) sll a);	
						when 5 =>    --	SRA
							if exe_imm = "0000000000000000" then
								a := 8;
							else 
								a := conv_integer(exe_imm);
							end if;
							exe_ans := to_stdlogicvector(to_bitvector(exe_b) sra a);
						when 6 | 7 | 9 =>    --   ADDIU3
							exe_ans := exe_a + exe_imm;
						when 10 | 13 |27 |28 =>    --	MTSP
							exe_ans := exe_a;
						when 11 =>    --    LI
							exe_ans := exe_imm;
						when 12 =>    --	CMPI
							if exe_a = exe_imm then
								exe_ans := "0000000000000000";
							else
								exe_ans := "0000000000000001";
							end if;
						when 14 | 15=>    -- LW_SP
							exe_addr := exe_a + exe_imm;
							exe_lw := '1';
						when 16 |17 =>    --	SW_SP
							exe_ans := exe_b;
							exe_addr := exe_a + exe_imm;
						when 18 =>    --	ADDU
							exe_ans := exe_a + exe_b;
						when 19 =>    --	SUBU
							exe_ans := exe_a - exe_b;
						when 21 =>    --	MFPC
							exe_ans := exe_pc;
						when 22 =>    --	SLLV
							a := conv_integer(exe_a);
							exe_ans := to_stdlogicvector(to_bitvector(exe_b) sll a);
						when 23 =>    --	AND
							exe_ans := exe_a and exe_b;
						when 24 =>    --	OR
							exe_ans := exe_a or exe_b;
						when 25 =>    --	CMP
							if exe_a = exe_b then
								exe_ans := "0000000000000000";
							else
								exe_ans := "0000000000000000" + 1;
							end if;
						when 26 =>    --	SRAV
							a := conv_integer(exe_a);
							exe_ans := to_stdlogicvector(to_bitvector(exe_b) sra a);
						when 29 =>    --	SLTU
							if conv_integer(exe_a) < conv_integer(exe_b) then
								exe_ans := "0000000000000001";
							else
								exe_ans := "0000000000000000";
							end if;
						when others =>    
					end case;
				when 2 =>
				when 3 =>
				when 4 =>
					pre_pc_by_exe <= '0';
					if_id_op_nop_exe <= '0';
					id_exe_op_nop_exe <= '0';
					id_exe_a_exe <= '0';
					id_exe_b_exe <= '0';
					exe_me_wb <= exe_wb;
					exe_me_op <= exe_op;
					exe_me_rz <= exe_rz;
					exe_me_ans <= exe_ans;
					exe_me_addr <= exe_addr;
					
					if exe_wb = '1' and id_op /= 0 then
						if exe_rz = id_rx then
							id_exe_a_exe <= '1';
							id_exe_a_from_exe <= exe_ans;
						end if;
						if exe_rz = id_ry then
							id_exe_b_exe <= '1';
							id_exe_b_from_exe <= exe_ans;
						end if;
					end if;
					
					if exe_lw = '1' and id_op /= 0 then
						if exe_rz = id_rx or exe_rz = id_ry then
							pre_pc_by_exe <= '1';
							pre_pc_from_exe <= exe_pc;
							if_id_op_nop_exe <= '1';
							id_exe_op_nop_exe <= '1';
						end if;
					end if;
					
					if exe_br = '1' then
						pre_pc_by_exe <= '1';
						if predict = '0' then 
							pre_pc_from_exe <= exe_pc2;
						else
							pre_pc_from_exe <= exe_pc + 1 ;
						end if;	
						predict <= not predict ;
						if_id_op_nop_exe <= '1';
						--id_exe_op_nop_exe <= '1';
					end if;
				when others =>
			end case;	
			if exe_cnt = 4 then
				exe_cnt := 0;
			else
				exe_cnt := exe_cnt + 1;
			end if;
		end if;
	end process;
	
	--ME
	process (clk)
	begin
		if clk'event and clk = '1' then
			case me_cnt is
				when 0 =>
					if pre_pc_by_exe = '1' then
						if_pc := pre_pc_from_exe;
					elsif pre_pc_by_id = '1' then
						if_pc := pre_pc_from_id	;
					else
						if_pc := pre_pc;
					end if;
					L <= if_pc;
					WE_ram1 <= '1';
					EN_ram1 <= '0';
					addr_ram1 <= "00" & if_pc;
					data_ram1 <= "ZZZZZZZZZZZZZZZZ";
				when 1 =>
					OE_ram1 <= '0';
				when 2 =>
					if_ins := data_ram1;
					OE_ram1 <= '1';	
					
					me_wb := exe_me_wb;
					me_op := exe_me_op;
					me_rz := exe_me_rz;
					
					
					me_mode := 0;
					
					case me_op is
						when 14 | 15 => --LW_SP  LW
							if exe_me_addr = "1011111100000000" then 
								
								EN_ram1 <= '1';
								WE_ram1 <= '1';
								OE_ram1 <= '1';
			   					
								rdn <= '1';
								wrn <= '1';
								data_ram1 <= "ZZZZZZZZZZZZZZZZ";
								me_mode := 1;
								
							elsif exe_me_addr = "1011111100000001" then 
								EN_ram1 <= '1';
								WE_ram1 <= '1';
								OE_ram1 <= '1';
							
								rdn <= '1';
								wrn <= '1';
								me_mode := 5;
							else -- lW
								
								EN_ram1 <= '0';
								WE_ram1 <= '1';
								OE_ram1 <= '1';
								rdn <= '1';
								wrn <= '1';
								
								data_ram1 <= "ZZZZZZZZZZZZZZZZ";
								addr_ram1 <= "00" & exe_me_addr;
								me_mode := 2;
								
							end if;
						when 16 | 17 => --SW_SP
							if exe_me_addr = "1011111100000000" then -- write_serial
 								
								EN_ram1 <= '1';
								WE_ram1 <= '1';
								OE_ram1 <= '1';
								rdn <= '1';
								wrn <= '1';
								
								data_ram1 <= exe_me_ans;
								me_mode := 3; 
							else -- SW
								
								EN_ram1 <= '0';
								WE_ram1 <= '1';
								OE_ram1 <= '1';
								rdn <= '1';
								wrn <= '1';
								
								data_ram1 <= exe_me_ans;
								addr_ram1 <= "00" & exe_me_addr;
								me_mode := 4;
							end if;
						when others =>
							me_data := exe_me_ans;
					end case;
				when 3 =>
					case me_mode is
						when 1 =>    --load_s
							rdn <= '0';
						when 2 =>    --LW
							OE_ram1 <= '0';
						when 3 =>    --write_s
							wrn <= '0';
						when 4 =>    --SW
							WE_ram1 <= '0';
						when others => 
					end case;
				when 4 =>
					case me_mode is
						when 1 =>    --load_s
							me_data := "00000000" & data_ram1(7 downto 0);
							rdn <= '1';  
						when 2 =>    --lw
							me_data := data_ram1;
							OE_ram1 <= '1';
						when 3 =>    --write_s
							wrn <= '1';
						when 4 =>    --sw
							WE_ram1 <= '1';
						when 5 =>
							me_data := "00000000000000" & (data_ready) & (tbre and tsre);
						when others => --do nothing
					end case;
					id_exe_a_me <= '0';
					id_exe_b_me <= '0';
					
					me_wb_wb <= me_wb;
					me_wb_rz <= me_rz;
					me_wb_data <= me_data;
					me_wb_op <= me_op;
					if me_wb = '1' and me_op /= 0 and id_op /= 0 then
						if me_rz = id_rx then  
							id_exe_a_me <= '1';
							id_exe_a_from_me <= me_data;
						end if;
						if me_rz = id_ry then
							id_exe_b_me <= '1';
							id_exe_b_from_me <= me_data;
						end if;
					end if;
				when others =>
			end case;
			if me_cnt = 4 then
				me_cnt := 0;
			else
				me_cnt := me_cnt + 1;
			end if;
		end if;
	end process;
		
	--WB
	process(clk)
	begin
		if clk'event and clk = '1' then
			case wb_cnt is
				when 0 =>
					if me_wb_wb = '1' then
						case me_wb_rz is
							when "0000" => r0 <= me_wb_data;
							when "0001" => r1 <= me_wb_data;
							when "0010" => r2 <= me_wb_data;
							when "0011" => r3 <= me_wb_data;
							when "0100" => r4 <= me_wb_data;
							when "0101" => r5 <= me_wb_data;
							when "0110" => r6 <= me_wb_data;
							when "0111" => r7 <= me_wb_data;
							when "1101" =>  T <= me_wb_data;
							when "1110" => SP <= me_wb_data;
							when "1111" => IH <= me_wb_data;
							when others => 
						end case;
					end if;
				when 1 =>
				when 2 =>
				when 3 =>
					
					
				when 4 =>
					if int_recover ='1' then
						r0 <= int_r0;
						r1 <= int_r1;
					end if;
					if me_wb_op = 30 then
						int_r0 <= r0;
						int_r1 <= r1;
						sp <= "1011111100010000";
						r0 <= int_imm;
						r1 <= int_pc;
					end if;
				when others =>
			end case;
			if wb_cnt = 4 then
				wb_cnt := 0;
			else
				wb_cnt := wb_cnt + 1;
			end if;
		end if;
	end process;
	--CLK
	process(clk_50)
		begin
		if do = '1' then 
			clk <= clk_50; 
		end if;
	end process;
	process(clk_1)
		begin
			if clk_1' event and clk_1 = '1' then
				do <= not do ;
			end if;
	end process;
end behavioral;
