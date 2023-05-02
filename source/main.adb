--  main.adb: Main function of the freestanding kernel.
--  Copyright (C) 2021 streaksu
--
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.

with Arch;
with Devices.Ramdev;
with Devices;
with VFS.File; use VFS.File;
with VFS;
with Lib.Cmdline;
with Lib.Messages;
with Lib.Panic;
with Userland.Loader;
with Userland.Process; use Userland.Process;
with Userland;
with Scheduler;
with Lib.Runtime;
pragma Unreferenced (Lib.Runtime);
with Config;

procedure Main is
   pragma SPARK_Mode (Off);

   Init_Arguments   : Userland.Argument_Arr (1 .. 1);
   Init_Environment : Userland.Environment_Arr (1 .. 0);

   Value     : String (1 .. 60);
   Value_Len : Natural;
   Found     : Boolean;
   Init_File : File_Acc;

   Init_Stdin  : constant String := "/dev/null";
   Init_Stdout : constant String := "/dev/debug";

   Proto   : constant Arch.Boot_Information := Arch.Get_Info;
   Cmdline : constant String := Proto.Cmdline (1 .. Proto.Cmdline_Len);
begin
   Lib.Messages.Put_Line (Config.Name & " version " & Config.Version);
   Lib.Messages.Put_Line ("Please report bugs/issues at " & Config.Bug_Site);
   Lib.Messages.Put_Line ("Command line: '" & Cmdline & "'");

   --  Initialize several subsystems.
   Userland.Process.Init;
   Devices.Init;
   VFS.Init;

   --  Load RAM files.
   if not Devices.Ramdev.Init (Proto.RAM_Files (1 .. Proto.RAM_Files_Len)) then
      Lib.Messages.Warn ("Could not load RAM files");
   end if;

   --  Initialize the scheduler.
   if not Scheduler.Init then
      Lib.Panic.Hard_Panic ("Could not initialize the scheduler");
   end if;

   --  Mount a root if specified.
   Lib.Cmdline.Get_Parameter
      (Cmdline, Lib.Cmdline.Root_Key, Value, Found, Value_Len);
   if Found and Value_Len /= 0 then
      if not VFS.Mount (Value (1 .. Value_Len), "/") then
         Lib.Messages.Warn ("Failed to mount " & Value (1 .. Value_Len));
      end if;
   end if;

   --  Init an init if specified.
   Lib.Cmdline.Get_Parameter
      (Cmdline, Lib.Cmdline.Init_Key, Value, Found, Value_Len);
   if Found and Value_Len /= 0 then
      Lib.Messages.Put_Line ("Booting init " & Value (1 .. Value_Len));
      Init_Arguments (1) := new String'(Value (1 .. Value_Len));
      Init_File := Open (Value (1 .. Value_Len), Read_Only);
      if Init_File = null or else Userland.Loader.Start_Program
         (Init_File, Init_Arguments, Init_Environment, Init_Stdin,
          Init_Stdout, Init_Stdout) = Error_PID
      then
         Lib.Panic.Hard_Panic ("Could not start init");
      end if;
      Close (Init_File);
   else
      Lib.Panic.Hard_Panic ("No init was specified");
   end if;

   --  Going idle into the scheduler.
   Scheduler.Idle_Core;
end Main;
