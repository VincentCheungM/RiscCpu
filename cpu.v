

//12.21 19:19检查latch
//12.28 发现少了Jump，减法的置位
//还差select_y, 那块的实现：以及gr的复位、flag的复位
//12.31完成branch hazard，为了提高速度，不模块化了
//1.1全面改进编码注意初始化的时候NOP不再是00000，所以不再将指令初始化为0
//同时完成了2个hazard control
//1.8 解决Load相隔的问题，现在试试相隔2条的问题,bug 解决
//1.8 把后面指令寄存器的位数缩减

// FSM for CPU control
`define idle 1'b0
`define exec 1'b1
// op code                                               
`define XOR   5'b00000           
`define LDIH  5'b00001           
`define JMPR  5'b00011
`define SLA 5'b00010
`define HALT  5'b00110
`define BN    5'b00111
`define ADDI  5'b00101
`define ADDC  5'b00100
`define SUB   5'b01100
`define SUBI  5'b01101
`define BNN   5'b01111
`define SRL   5'b01110
`define SLL   5'b01010
`define JUMP 5'b01011
`define STALL1 5'b01001
`define AND   5'b01000
`define CMP   5'b11000
`define STALL2   5'b11001
`define BNZ   5'b11011
`define STORE  5'b11010
`define LOAD  5'b11110
`define BZ    5'b11111
//`define BNZ   5'b11101
`define ADD   5'b11100
`define SUBC  5'b10100
//`define BC    5'b10101
`define BNC   5'b10111
`define SRA   5'b10110
`define NOP   5'b10010
`define BC	  5'b10011
//            5'b10001
`define OR    5'b10000
//
`define BRANCH 2'b11
`define R3 2'b00
`define R1 1'b1





module pccpu(
	input clock, reset,
	input start, enable,
	input [15:0]d_datain, i_datain,
	input [3:0] select_y,
	output [7:0] i_addr,
	output [7:0]d_addr,
	output d_we,
	output reg[15:0]  y,
	output [15:0]d_dataout
	);
	
			  
	//declaration-----------------------------
	reg[7:0] pc;//指令计数器，暂时其值则为指令地址值
	reg[15:0] id_ir;//指令寄存器
	reg[15:0] gr[0:7];//8个16位的通用寄存器 初始化？
	reg[7:0] ex_ir, wb_ir, mem_ir;
	reg[15:0]  smdr, reg_C, smdr_1, reg_C1;
	reg[15:0] reg_B, reg_A;
	reg zf, nf, cf;
	reg dw;
	//wire cout;
	reg cout;
	reg [15:0] ALUo;
	//wire[15:0] ALUo;
	//---------------------------------------
	//************************************************//
//* You need to complete the design below        *//
//* by yourself according to your operation set  *//
//************************************************//

//************* CPU control *************//
	//涉及变量 state next_state enable start wb_ir
	reg state = `idle;
	reg next_state = `idle;
	
always @(posedge clock or posedge reset)
	begin
		if (reset)
			state <= `idle;
		else
			state <= next_state;
	end
	
always @(*)
	begin
		case (state)
			`idle : 
				if ((enable == 1'b1) 
				&& (start == 1'b1))
					next_state <= `exec;
				else	
					next_state <= `idle;
			`exec :
				if ((enable == 1'b0) 
				|| (wb_ir[7:3] == `HALT))
					next_state <= `idle;
				else
					next_state <= `exec;
			default : next_state <= `idle;
		endcase
	end
	
	
	
//************* IF *************//                                
	//计数器pc mem_ir
always @(posedge clock or posedge reset)//
	begin
		if (reset)
			begin
				id_ir <= 16'b1001_0000_0000_0000;
				pc <= 8'b0000_0000;
			end
			
		else if (state == `exec)
			begin
				if(id_ir[12:11] == `BRANCH)//`BRANCH即所有跳转指令，定为11，故将所有跳转指令以11结尾
				begin
					id_ir <= {`STALL2,11'b000_0000_0000};
					pc <= pc;
				end
				else if((id_ir[15:11] == `STALL2)//当上一个指令为STALL2时再插入一个STALL1 指令
					||(id_ir[15:11]==`LOAD&&{i_datain[3:0]}=={1'b0,id_ir[10:8]})//判断两个加数是否与写回寄存器相等
					//下一指令的r3 == writeback_gr即冲突
					||(id_ir[15:11]==`LOAD&&{i_datain[7:4]}=={1'b0,id_ir[10:8]})
					//下一指令的r2 == writeback_gr即冲突
					||(id_ir[15:11]==`LOAD&&{i_datain[11:8]}=={`R1,id_ir[10:8]})
					)//下一指令的使用R1且r1 == writeback_gr即冲突				
				begin
					//$display("%b:%b:%h:%h",id_ir,i_datain,ALUo,reg_C);
					id_ir <= {`STALL1,11'b000_0000_0000};
					pc <= pc;
				end
				else 
				begin
					id_ir <= i_datain;
					if(((mem_ir[7:3] == `BZ)&& (zf == 1'b1)) 
					|| ((mem_ir[7:3] == `BN)&& (nf == 1'b1))
					|| ((mem_ir[7:3] == `BC)&& (cf == 1'b1))
					|| ((mem_ir[7:3] == `BNZ)&& (zf == 1'b0)) 
					|| ((mem_ir[7:3] == `BNN)&& (nf == 1'b0))
					|| ((mem_ir[7:3] == `BNC)&& (cf == 1'b0)) 
					|| (mem_ir[7:3] == `JUMP)
					|| (mem_ir[7:3] == `JMPR))
					//这层只处理跳转，所有的加法运算都在ALU中执行完毕
					begin 	
						pc <= reg_C[7:0];
					end
					else
					begin 
					pc <= pc + 1'b1;
					end
				end
			end
	end

assign i_addr = pc;//i-mem 地址
		
	//************* ID *************//
	//ex_ir,reg_A, reg_B, gr,smdr这层涉及变量
	always @(posedge clock or posedge reset)//
	begin
		if (reset)
			begin
				ex_ir <= 8'b1001_0000;
				reg_A <= 16'b0000_0000_0000_0000;
				reg_B <= 16'b0000_0000_0000_0000;
				smdr <= 16'b0000_0000_0000_0000;
			 
			end
			
		else if (state == `exec)
			begin				
				ex_ir <= id_ir[15:8];
				//$display("before %b:%b:%b",wb_ir,ex_ir,id_ir);
				//$display("this stage %b:%b:%b:%h:%h\n",mem_ir,ex_ir,id_ir,reg_A,reg_B);
				if(id_ir[11]==`R1)//`R1指ALU中会使用到R1作为操作数的指令
					begin
					if(ex_ir[2:0]==id_ir[10:8])//
							begin
								//$display("`ex _id a -- aluo");
								reg_A <= ALUo; //相邻指令相关，转发计算结果
							end
					else if(mem_ir[2:0]==id_ir[10:8]||wb_ir[2:0]==id_ir[10:8]/*||ex_ir[2:0]==id_ir[10:8]*/)
							begin
							if(ex_ir[7:3] == `STALL1&&mem_ir[2:0]==id_ir[10:8])
								begin		
									//$display("`STALL a datain");
									reg_A <= d_datain; //转发输入
								end
							else if(ex_ir[7:3] == `LOAD)
								begin
									//$display("`load a c1");
									//与上上条指令且为输入，相关转发输入
									reg_A <= reg_C1;
								end
							else
								begin
									//$display("now %b:%b:%b",wb_ir,ex_ir,id_ir);
									//$display("`forwad a c");
									reg_A <= reg_C;//与上上条指令相关，转发计算结果
								end
							end
					else	
						reg_A <= gr[id_ir[10:8]];
					end
				else 
					begin
					if(ex_ir[2:0]==id_ir[6:4])//未及细究 d:r1 --- s:r1
							begin
								//$display("`forwad(r2) a aluo");
								reg_A <= ALUo;
							end 
					else if(mem_ir[2:0]==id_ir[6:4]||wb_ir[2:0]==id_ir[6:4])
							begin
							if(ex_ir[7:3] == `STALL1&&mem_ir[2:0]==id_ir[6:4])
								begin
									//$display("`stall (r2) a datain");
									reg_A <= d_datain; 
								end
							else if(wb_ir[2:0]==id_ir[6:4])
								begin
									//$display("`forwad(r2) a c1");
									reg_A <= reg_C1;	
								end
							else
								begin
									//$display("`forwad(r2) a c");
									reg_A <= reg_C;     
								end
							end
					//以上reg_A = r1 reg_B基本上是{val2,val3}
					//以下reg_A = r2 reg_B基本上为立即数	
					else
						reg_A <= gr[id_ir[6:4]];
					end


				if(id_ir[4:3]==`R3)//use r3 to alu
					begin
					//$display("r3 %h :%b :%b",pc,ex_ir,id_ir);
					if(ex_ir[2:0]==id_ir[2:0])//未及细究 d:r1 --- s:r1
						begin
							//$display("`forwad(r3) b aluo");
							reg_B <= ALUo; 
						end
					else if(mem_ir[2:0]==id_ir[2:0]||wb_ir[2:0]==id_ir[2:0])
						begin
							if(ex_ir[7:3] == `STALL1)
								begin
									//$display("`forwad(r3) b datain");
									reg_B <= d_datain; 
								end
							else if(wb_ir[2:0]==id_ir[2:0])
								begin
									//$display("`forwad(r3) b c1");
									reg_B <= reg_C1;
								end
							else
								begin
									//$display("`forwad(r3) b c");
									reg_B <= reg_C; 
								end
						end
					else
							reg_B <= gr[id_ir[2:0]];
					end

				else  
					begin
					if(id_ir[15:11]==	`LDIH)
						reg_B <= {id_ir[7:0], 8'b0000_0000};
					else if(id_ir[12:11]==`BRANCH
							||id_ir[15:11]==`ADDI
							||id_ir[15:11]==`SUBI)
						reg_B <= {8'b0000_0000, id_ir[7:0]};
					else
						reg_B <= {12'b0000_0000_0000, id_ir[3:0]};
				   end
					
				if(id_ir[15:11]==`STORE)
					begin
					if(mem_ir[2:0]==id_ir[10:8])//用r1位置指令且上一指令为写入指令,目前来说逻辑层数变多了
							begin 
							if(mem_ir[7:3] == `LOAD)
								smdr <= d_datain;
							else
								smdr <= ALUo;
							end
					else
							smdr <= gr[id_ir[10:8]];
					end
				else
					smdr <= smdr;
				
			end

	end		
//alu 输出参数是wire型的
always@(reg_A or reg_B or ex_ir[7:3] or reset or cf)
	begin
		if(reset)
			begin
				ALUo <= 0;
				cout <= 0;
			end
	//需要考虑进位标志的只有加法，其余的应该将该标志维持原状(暂时这么决定
		else
			begin
				//$display("%b",ex_ir);
			//$display("ALU::%b:%h:%h:%h",ex_ir,reg_A,ALUo,reg_B);
				if(ex_ir[4:3] == `BRANCH||ex_ir[7:3]==`LOAD
				||ex_ir[7:3]==`STORE||ex_ir[7:3]==`LDIH||
				ex_ir[7:3]==`ADDI||ex_ir[7:3]==`ADD
				)begin
					{cout, ALUo} <= reg_A + reg_B;
					//$display("+  %b",ex_ir);
					end
				else if(ex_ir[7:3] ==`SUB||ex_ir[7:3] ==`SUBI||ex_ir[7:3] == `CMP)
					begin 
						//$display("-  %b",ex_ir);
						{cout, ALUo}<= reg_A - reg_B;
					end
				else if(ex_ir[7:3]==`SUBC)
					begin {cout, ALUo}<= (reg_A - reg_B) - cf ; end
				else if(ex_ir[7:3]==`ADDC)
					begin {cout, ALUo} <= (reg_A + reg_B) + cf; end
				else if(ex_ir[7:3]==`AND)
					begin {cout, ALUo}<= reg_A & reg_B;         end
				else if(ex_ir[7:3]==`OR)
					begin {cout, ALUo}<= reg_A | reg_B;         end
				else if(ex_ir[7:3]==`XOR)
					begin {cout, ALUo}<= reg_A ^ reg_B;         end
				else if(ex_ir[7:3]==`SLL)
					begin {cout, ALUo}<= reg_A << reg_B;        end
				else if(ex_ir[7:3]==`SLA)
					begin {cout, ALUo}<= reg_A <<< reg_B;       end
				else if(ex_ir[7:3]==`SRA)
					begin ALUo <= reg_A >>> reg_B; cout<=cf;    end
				else if(ex_ir[7:3]==`SRL)
					begin ALUo<= reg_A >> reg_B;  cout<=cf;     end
				else
					begin {cout, ALUo} <= {cf,16'b0};           end
			end		
	end
//alu alu1(.reg_A(reg_A), .reg_B(reg_B), .cf(cf), .ALUo(ALUo),.ir(ex_ir[15:11]), .cout(cout), .reset(reset));
//************* EX *************//
	//reg_C, mem_ir, ALUo,flags,dw,smdr1
always @(posedge clock or posedge reset)//
	begin
		if (reset)
			begin
				mem_ir <= 8'b1001_0000;
				reg_C <= 16'b0000_0000_0000_0000;
				zf <= 0;
				cf <= 0;
				nf <= 0;
			end	
		else if (state == `exec)
			begin
				mem_ir <= ex_ir;
				reg_C <= ALUo;
				if ((ex_ir[3] == `R1) 
				|| (ex_ir[7:3] == `ADDI)
				|| (ex_ir[7:3] == `LDIH)
				|| (ex_ir[7:3] == `SUBI))
					begin				
						if (reg_C == 16'b0000_0000_0000_0000)
							zf <= 1'b1;
						else
							zf <= 1'b0;
						nf <= reg_C[15];
						cf <= cout;
					end
				else
					begin
					//理论上只有上述几种情形会改变flag的值
						zf <= zf;
						nf <= nf;
						cf <= cf;
					end
				if (ex_ir[7:3] == `STORE)
					begin
						dw <= 1'b1;
						smdr_1 <= smdr;
					end
				else
					begin
					dw <= 1'b0;
					smdr_1 <= smdr_1;
					end
			end
			
	end
//************* MEM *************//
	//wb_ir,reg_C1
always @(posedge clock or posedge reset)
	begin
		if (reset)
			begin
				wb_ir <= 8'b1001_0000;
				reg_C1 <= 16'b0000_0000_0000_0000;
			end	
		else if (state == `exec)
			begin
				wb_ir <= mem_ir;				
				if (mem_ir[7:3] == `LOAD)
					reg_C1 <= d_datain;
				else
					reg_C1 <= reg_C;
			end
		else
			begin
				wb_ir <= wb_ir;
				reg_C1 <= reg_C1;
			end
	end	
	
assign d_we = dw;
assign d_dataout = smdr_1;
assign d_addr = reg_C[7:0];
//************* WB *************//
	//写回r1寄存器
always @(posedge clock or posedge reset)
	begin
		if (reset)
			begin
				gr[0] <= 16'b0000_0000_0000_0000;
				gr[1] <= 16'b0000_0000_0000_0000;
				gr[2] <= 16'b0000_0000_0000_0000;
				gr[3] <= 16'b0000_0000_0000_0000;
				gr[4] <= 16'b0000_0000_0000_0000;
				gr[5] <= 16'b0000_0000_0000_0000;
				gr[6] <= 16'b0000_0000_0000_0000;
				gr[7] <= 16'b0000_0000_0000_0000;
			end	
		else if (state == `exec)
			begin
				if ((wb_ir[7:3] == `NOP)
				||(wb_ir[4:3] == `BRANCH)
				||(wb_ir[7:3] == `HALT)
				||(wb_ir[7:3] == `STALL2)
				||(wb_ir[7:3] ==`STALL1)
				||(wb_ir[7:3] ==`STORE)
				||(wb_ir[7:3] ==`CMP))
					gr[wb_ir[2:0]] <= gr[wb_ir[2:0]];					
				else
					gr[wb_ir[2:0]] <= reg_C1;
			end
		else
			gr[wb_ir[2:0]] <= gr[wb_ir[2:0]];
	end

// for debugging
always @(select_y or gr[1] or gr[2] or gr[3] or gr[4] or gr[5] or gr[6]
         or gr[7] or reg_A or reg_B or reg_C or reg_C1 or smdr or id_ir
         or dw or zf or nf or pc)
   begin
     case (select_y)
       4'b0001 : y = gr[1];
       4'b0010 : y = gr[2];
       4'b0011 : y = gr[3];
       4'b0100 : y = gr[4];
       4'b0101 : y = gr[5];
       4'b0110 : y = gr[6];
       4'b0111 : y = gr[7];
       4'b1000 : y = reg_A;
       4'b1001 : y = reg_B;
       4'b1011 : y = reg_C;
       4'b1100 : y = reg_C1;
       4'b1101 : y = smdr;
       4'b1110 : y = id_ir;
       default : y = {3'b000, dw, 2'b00, zf, nf, pc};
     endcase
   end
	
	
	
	
endmodule



