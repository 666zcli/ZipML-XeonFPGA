--------------------------------------------------------------------------
--  Copyright (C) 2018 Kaan Kara - Systems Group, ETH Zurich

--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU Affero General Public License as published
--  by the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.

--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU Affero General Public License for more details.

--  You should have received a copy of the GNU Affero General Public License
--  along with this program. If not, see <http://www.gnu.org/licenses/>.
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity request_receive is
generic(ADDRESS_WIDTH : integer := 32;
		LOG2_MAX_iBATCHSIZE : integer := 9;
		LOG2_MAX_NUMFEATURES: integer := 15);
port (
	clk: in std_logic;
	resetn : in std_logic;

	start : in std_logic;
	restart : in std_logic;

	read_request : out std_logic;
	read_request_address : out std_logic_vector(ADDRESS_WIDTH-1 downto 0);
	read_request_tid : out std_logic_vector(15 downto 0);
	read_request_almostfull : in std_logic;

	read_response : in std_logic;
	read_response_data : in std_logic_vector(511 downto 0);
	read_response_tid : in std_logic_vector(15 downto 0);

	requested_reads_count : out std_logic_vector(31 downto 0);
	reorder_free_count : out std_logic_vector(31 downto 0);
	out_residual_valid : out std_logic;
	out_b_valid : out std_logic;
	out_a_valid : out std_logic;
	out_index : out std_logic_vector(LOG2_MAX_iBATCHSIZE-1 downto 0);
	out_data : out std_logic_vector(511 downto 0);

	external_free_count : in std_logic_vector(8 downto 0);
	enable_staleness : in std_logic;
	read_size_from_memory : in std_logic;
	a_address : in std_logic_vector(ADDRESS_WIDTH-1 downto 0);
	b_address : in std_logic_vector(ADDRESS_WIDTH-1 downto 0);
	step_address : in std_logic_vector(ADDRESS_WIDTH-1 downto 0);
	residual_address : in std_logic_vector(ADDRESS_WIDTH-1 downto 0);
	number_of_features : in std_logic_vector(LOG2_MAX_NUMFEATURES downto 0);
	number_of_batches : in std_logic_vector(15 downto 0);
	batch_size : in std_logic_vector(15 downto 0));
end request_receive;

architecture behavioral of request_receive is

signal iNUMBER_OF_FEATURES : unsigned(LOG2_MAX_NUMFEATURES downto 0) := (others => '0');
signal iNUMBER_OF_OFFSET_LINES : unsigned(LOG2_MAX_NUMFEATURES-4 downto 0) := (others => '0');
signal iNUMBER_OF_BATCHES : unsigned(15 downto 0) := (others => '0');
signal iBATCH_SIZE : unsigned(15 downto 0) := (others => '0');
signal iREAD_SIZE : unsigned(15 downto 0) := (others => '0');
signal iRECEIVE_SIZE : unsigned(15 downto 0) := (others => '0');
signal iBATCH_OFFSET : unsigned(31 downto 0) := (others => '0');
signal iCOLUMN_SIZE : unsigned(31 downto 0) := (others => '0');

-- 0 read column offsets, 1 read residual, 2 read b, 3 read a
signal read_state : std_logic_vector(1 downto 0) := (others => '0');
signal receive_state : std_logic_vector(1 downto 0) := (others => '0');

signal NumberOfPendingReads : unsigned(31 downto 0) := (others => '0');
signal NumberOfRequestedReads : unsigned(31 downto 0) := (others => '0');
signal residual_NumberOfRequestedReads : unsigned(31 downto 0) := (others => '0');
signal b_NumberOfRequestedReads : unsigned(31 downto 0) := (others => '0');
signal a_NumberOfRequestedReads : unsigned(31 downto 0) := (others => '0');
signal NumberOfReceivedReads : unsigned(31 downto 0) := (others => '0');
signal residual_NumberOfReceivedReads : unsigned(31 downto 0) := (others => '0');
signal b_NumberOfReceivedReads : unsigned(31 downto 0) := (others => '0');
signal a_NumberOfReceivedReads : unsigned(31 downto 0) := (others => '0');

signal offset_read_index : unsigned(LOG2_MAX_NUMFEATURES-4-1 downto 0) := (others => '0');
signal feature_index : unsigned(LOG2_MAX_NUMFEATURES-1 downto 0) := (others => '0');
signal feature_index_in_line : integer range 0 to 15;
signal feature_receive_index : unsigned(LOG2_MAX_NUMFEATURES-1 downto 0) := (others => '0');
signal batch_index : unsigned(15 downto 0) := (others => '0');
signal i_index : unsigned(LOG2_MAX_iBATCHSIZE-1 downto 0) := (others => '0');
signal i_receive_index : unsigned(LOG2_MAX_iBATCHSIZE-1 downto 0) := (others => '0');

signal new_column_read_allowed : std_logic;

signal column_offset_raddr : std_logic_vector(LOG2_MAX_NUMFEATURES-4-1 downto 0);
signal column_offset_waddr : std_logic_vector(LOG2_MAX_NUMFEATURES-4-1 downto 0);
signal column_offset_din : std_logic_vector(511 downto 0);
signal column_offset_we : std_logic;
signal column_offset_dout : std_logic_vector(511 downto 0);

signal column_previous_readsize_raddr : std_logic_vector(LOG2_MAX_NUMFEATURES-4-1 downto 0);
signal column_previous_readsize_waddr : std_logic_vector(LOG2_MAX_NUMFEATURES-4-1 downto 0);
signal column_previous_readsize_din : std_logic_vector(511 downto 0);
signal column_previous_readsize_we : std_logic;
signal column_previous_readsize_dout : std_logic_vector(511 downto 0);

signal reorder_start_address_adjust : std_logic;
signal reorder_start_address : std_logic_vector(15 downto 0);
signal reordered_buffer_free_count : std_logic_vector(31 downto 0);
signal reordered_response_data : std_logic_vector(511 downto 0);
signal reordered_resonse : std_logic;

component reorder
generic(
	LOG2_BUFFER_DEPTH : integer := 8;
	ADDRESS_WIDTH : integer := 32);
port (
	clk : in std_logic;
	resetn : in std_logic;
	start_address_adjust : std_logic;
	start_address : in std_logic_vector(ADDRESS_WIDTH-1 downto 0);
	in_trigger : in std_logic;
	in_address : in std_logic_vector(ADDRESS_WIDTH-1 downto 0);
	in_data : in std_logic_vector(511 downto 0);
	buffer_free_count : out std_logic_vector(31 downto 0);
	out_data : out std_logic_vector(511 downto 0);
	out_valid : out std_logic);
end component;

component simple_dual_port_ram_single_clock
generic(
	DATA_WIDTH : natural := 8;
	ADDR_WIDTH : natural := 6);
port(
	clk		: in std_logic;
	raddr	: in std_logic_vector(ADDR_WIDTH-1 downto 0);
	waddr	: in std_logic_vector(ADDR_WIDTH-1 downto 0);
	data	: in std_logic_vector((DATA_WIDTH-1) downto 0);
	we		: in std_logic := '1';
	q		: out std_logic_vector((DATA_WIDTH -1) downto 0));
end component;

begin

requested_reads_count <= std_logic_vector(NumberOfRequestedReads);
reorder_free_count <= std_logic_vector(reordered_buffer_free_count);

reordering: reorder
generic map (
	LOG2_BUFFER_DEPTH => 8,
	ADDRESS_WIDTH => 16)
port map (
	clk => clk,
	resetn => resetn,
	start_address_adjust => reorder_start_address_adjust,
	start_address => reorder_start_address,
	in_trigger => read_response,
	in_address => read_response_tid,
	in_data => read_response_data,
	buffer_free_count => reordered_buffer_free_count,
	out_data => reordered_response_data,
	out_valid => reordered_resonse);

column_offset_raddr <= std_logic_vector( feature_index(LOG2_MAX_NUMFEATURES-1 downto 4) );
column_offset_store: simple_dual_port_ram_single_clock
generic map (
	DATA_WIDTH => 512,
	ADDR_WIDTH => LOG2_MAX_NUMFEATURES-4)
port map (
	clk => clk,
	raddr => column_offset_raddr,
	waddr => column_offset_waddr,
	data => column_offset_din,
	we => column_offset_we,
	q => column_offset_dout);

column_previous_readsize_raddr <= std_logic_vector( feature_index(LOG2_MAX_NUMFEATURES-1 downto 4) );
column_previous_readsize_store: simple_dual_port_ram_single_clock
generic map (
	DATA_WIDTH => 512,
	ADDR_WIDTH => LOG2_MAX_NUMFEATURES-4)
port map (
	clk => clk,
	raddr => column_previous_readsize_raddr,
	waddr => column_previous_readsize_waddr,
	data => column_previous_readsize_din,
	we => column_previous_readsize_we,
	q => column_previous_readsize_dout);


feature_index_in_line <= to_integer(feature_index(3 downto 0));
process(clk)
begin
if clk'event and clk = '1' then
	iNUMBER_OF_FEATURES <= unsigned(number_of_features);
	iNUMBER_OF_BATCHES <= unsigned(number_of_batches);
	iBATCH_SIZE <= unsigned(batch_size);
	iBATCH_OFFSET <= batch_index*iBATCH_SIZE;
	iCOLUMN_SIZE <= iNUMBER_OF_BATCHES*iBATCH_SIZE;
	if iNUMBER_OF_FEATURES(3 downto 0) > 0 then
		iNUMBER_OF_OFFSET_LINES <= iNUMBER_OF_FEATURES(LOG2_MAX_NUMFEATURES downto 4) + 1;
	else
		iNUMBER_OF_OFFSET_LINES <= iNUMBER_OF_FEATURES(LOG2_MAX_NUMFEATURES downto 4);
	end if;

	out_data <= reordered_response_data;

	NumberOfPendingReads <= NumberOfRequestedReads - NumberOfReceivedReads;

	if resetn = '0' or restart = '1' then
		read_request <= '0';

		iREAD_SIZE <= (others => '0');
		iRECEIVE_SIZE <= (others => '0');

		out_residual_valid <= '0';
		out_b_valid <= '0';
		out_a_valid <= '0';

		read_state <= B"00";
		receive_state <= B"00";

		NumberOfRequestedReads <= (others => '0');
		residual_NumberOfRequestedReads <= (others => '0');
		b_NumberOfRequestedReads <= (others => '0');
		a_NumberOfRequestedReads <= (others => '0');
		NumberOfReceivedReads <= (others => '0');
		residual_NumberOfReceivedReads <= (others => '0');
		b_NumberOfReceivedReads <= (others => '0');
		a_NumberOfReceivedReads <= (others => '0');

		offset_read_index <= (others => '0');
		feature_index <= (others => '0');
		feature_receive_index <= (others => '0');
		batch_index <= (others => '0');
		i_index <= (others => '0');
		i_receive_index <= (others => '0');

		new_column_read_allowed <= '1';

		reorder_start_address_adjust <= '0';
	else

		-- Request lines
		read_request <= '0';
		reorder_start_address_adjust <= '0';
		column_previous_readsize_we <= '0';
		if start = '1' and read_request_almostfull = '0' and batch_index <= iNUMBER_OF_BATCHES and new_column_read_allowed = '1'
			and NumberOfPendingReads < unsigned(reordered_buffer_free_count)
			and NumberOfPendingReads < unsigned(external_free_count)
		then
			read_request <= '1';
			read_request_tid <= B"00" & std_logic_vector(NumberOfRequestedReads(13 downto 0));
			NumberOfRequestedReads <= NumberOfRequestedReads + 1;
			if NumberOfRequestedReads = 0 then
				reorder_start_address_adjust <= '1';
				reorder_start_address <= (others => '0');
			end if;

			if read_state = B"00" then
				read_request_address <= std_logic_vector(unsigned(a_address) + offset_read_index);

				column_previous_readsize_we <= '1';
				column_previous_readsize_din <= (others => '0');
				column_previous_readsize_waddr <= std_logic_vector( offset_read_index );

				if offset_read_index = iNUMBER_OF_OFFSET_LINES-1 then
					offset_read_index <= (others => '0');
					new_column_read_allowed <= '0';
					read_state <= B"01";
				else
					offset_read_index <= offset_read_index + 1;
				end if;
			elsif read_state = B"01" then --read residual
				read_request_address <= std_logic_vector(unsigned(residual_address) + iBATCH_OFFSET + i_index);
				if i_index = iBATCH_SIZE-1 then
					i_index <= (others => '0');
					read_state <= B"10";
				else
					i_index <= i_index + 1;
				end if;
				residual_NumberOfRequestedReads <= residual_NumberOfRequestedReads + 1;
			elsif read_state = B"10" then --read b
				read_request_address <= std_logic_vector(unsigned(b_address) + iBATCH_OFFSET + i_index);
				if i_index = iBATCH_SIZE-1 then
					i_index <= (others => '0');
					read_state <= B"11";
				else
					i_index <= i_index + 1;
				end if;
				b_NumberOfRequestedReads <= b_NumberOfRequestedReads + 1;
			else -- read a
				read_request_address(ADDRESS_WIDTH-1 downto 32) <= (others => '0');
				read_request_address(31 downto 0) <= std_logic_vector(	
															unsigned( column_offset_dout( (feature_index_in_line+1)*32-1 downto feature_index_in_line*32 ) ) +
															unsigned( column_previous_readsize_dout( (feature_index_in_line+1)*32-1 downto feature_index_in_line*32 ) ) +
															i_index);
				if read_size_from_memory = '1' then
					if i_index = 0 then
						new_column_read_allowed <= '0';
						iREAD_SIZE <= (others => '0');
					end if;
				else
					iREAD_SIZE <= iBATCH_SIZE;
				end if;

				if i_index = iREAD_SIZE-1 then
					new_column_read_allowed <= enable_staleness;
					i_index <= (others => '0');	
					if feature_index = iNUMBER_OF_FEATURES-1 then
						read_state <= B"01";
						feature_index <= (others => '0');
						batch_index <= batch_index + 1;
					else
						feature_index <= feature_index + 1;
					end if;
					column_previous_readsize_we <= '1';
					column_previous_readsize_din <= column_previous_readsize_dout;
					column_previous_readsize_din((feature_index_in_line+1)*32-1 downto feature_index_in_line*32) <= std_logic_vector( unsigned( column_previous_readsize_dout((feature_index_in_line+1)*32-1 downto feature_index_in_line*32) ) + iREAD_SIZE );
					column_previous_readsize_waddr <= std_logic_vector( feature_index(LOG2_MAX_NUMFEATURES-1 downto 4) );
				else
					i_index <= i_index + 1;
				end if;

				a_NumberOfRequestedReads <= a_NumberOfRequestedReads + 1;
			end if;
		end if;

		-- Receive lines
		column_offset_we <= '0';
		out_residual_valid <= '0';
		out_b_valid <= '0';
		out_a_valid <= '0';
		if reordered_resonse = '1' then
			NumberOfReceivedReads <= NumberOfReceivedReads + 1;
			out_index <= std_logic_vector(i_receive_index);

			if receive_state = B"00" then
				column_offset_we <= '1';
				column_offset_din <= reordered_response_data;
				column_offset_waddr <= std_logic_vector( i_receive_index(LOG2_MAX_NUMFEATURES-4-1 downto 0) );
				if i_receive_index = iNUMBER_OF_OFFSET_LINES-1 then
					i_receive_index <= (others => '0');
					new_column_read_allowed <= '1';
					receive_state <= B"01";
				else
					i_receive_index <= i_receive_index + 1;
				end if;
			elsif receive_state = B"01" then --receive residual
				out_residual_valid <= '1';
				if i_receive_index = iBATCH_SIZE-1 then
					i_receive_index <= (others => '0');
					receive_state <= B"10";
				else
					i_receive_index <= i_receive_index + 1;
				end if;
				residual_NumberOfReceivedReads <= residual_NumberOfReceivedReads + 1;
			elsif receive_state = B"10" then --receive b
				out_b_valid <= '1';
				if i_receive_index = iBATCH_SIZE-1 then
					i_receive_index <= (others => '0');
					receive_state <= B"11";
				else
					i_receive_index <= i_receive_index + 1;
				end if;
				b_NumberOfReceivedReads <= b_NumberOfReceivedReads + 1;
			else --receive a

				if read_size_from_memory = '1' then
					if i_receive_index = 0 then
						new_column_read_allowed <= '1';
						iREAD_SIZE <= unsigned(reordered_response_data(15 downto 0));
						iRECEIVE_SIZE <= unsigned(reordered_response_data(15 downto 0));
					else
						out_a_valid <= '1';
					end if;
				else
					iRECEIVE_SIZE <= iBATCH_SIZE;
					out_a_valid <= '1';
				end if;

				if i_receive_index = iRECEIVE_SIZE-1 then
					new_column_read_allowed <= '1';
					i_receive_index <= (others => '0');
					if feature_receive_index = iNUMBER_OF_FEATURES-1 then
						receive_state <= B"01";
						feature_receive_index <= (others => '0');
					else
						feature_receive_index <= feature_receive_index + 1;
					end if;
				else
					i_receive_index <= i_receive_index + 1;
				end if;

				a_NumberOfReceivedReads <= a_NumberOfReceivedReads + 1;
			end if;
		end if;

	end if;
end if;
end process;

end architecture;