--  arch-stivale2.ads: Specification of stivale2 utilities and tags.
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

with System;
with Interfaces; use Interfaces;
with Memory;     use Memory;

package Arch.Stivale2 with SPARK_Mode => Off is
   --  IDs of several tags.
   RSDP_ID   : constant := 16#9E1786930A375E78#;
   Memmap_ID : constant := 16#2187F79E8612DE07#;
   SMP_ID    : constant := 16#34D1D96339647025#;

   --  Stivale2 header passed by the bootloader to kernel.
   type Header is record
      BootloaderBrand   : String (1 .. 64);
      BootloaderVersion : String (1 .. 64);
      Tags              : Physical_Address;
   end record;
   for Header use record
      BootloaderBrand   at 0 range    0 ..  511;
      BootloaderVersion at 0 range  512 .. 1023;
      Tags              at 0 range 1024 .. 1087;
   end record;
   for Header'Size use 1088;

   --  Stivale2 tag passed in front of all specialized tags.
   type Tag is record
      Identifier : Unsigned_64;
      Next       : Physical_Address;
   end record;
   for Tag use record
      Identifier at 0 range  0 ..  63;
      Next       at 0 range 64 .. 127;
   end record;
   for Tag'Size use 128;

   type RSDP_Tag is record
      TagInfo      : Tag;
      RSDP_Address : Physical_Address;
   end record;
   for RSDP_Tag use record
      TagInfo      at 0 range   0 .. 127;
      RSDP_Address at 0 range 128 .. 191;
   end record;
   for RSDP_Tag'Size use 192;

   Memmap_Entry_Usable                 : constant := 1;
   Memmap_Entry_Reserved               : constant := 2;
   Memmap_Entry_ACPI_Reclaimable       : constant := 3;
   Memmap_Entry_ACPI_NVS               : constant := 4;
   Memmap_Entry_Bad                    : constant := 5;
   Memmap_Entry_Bootloader_Reclaimable : constant := 16#1000#;
   Memmap_Entry_Kernel_And_Modules     : constant := 16#1001#;
   Memmap_Entry_Framebuffer            : constant := 16#1002#;

   type Memmap_Entry is record
      Base      : Physical_Address;
      Length    : Size;
      EntryType : Unsigned_32;
      Unused    : Unsigned_32;
   end record;
   for Memmap_Entry use record
      Base      at 0 range   0 ..  63;
      Length    at 0 range  64 .. 127;
      EntryType at 0 range 128 .. 159;
      Unused    at 0 range 160 .. 191;
   end record;
   for Memmap_Entry'Size use 192;

   type Memmap_Entries is array (Natural range <>) of Memmap_Entry;
   type Memmap_Tag (Count : Natural) is record
      TagInfo : Tag;
      Entries : Memmap_Entries (1 .. Count);
   end record;
   for Memmap_Tag use record
      TagInfo at 0 range   0 .. 127;
      Count   at 0 range 128 .. 191;
   end record;

   --  Stivale2 SMP protocol.
   type SMP_Core is record
      Processor_ID   : Unsigned_32;
      LAPIC_ID       : Unsigned_32;
      Target_Stack   : System.Address;
      Goto_Address   : System.Address;
      Extra_Argument : Unsigned_64;
   end record;
   for SMP_Core use record
      Processor_ID   at 0 range   0 ..  31;
      LAPIC_ID       at 0 range  32 ..  63;
      Target_Stack   at 0 range  64 .. 127;
      Goto_Address   at 0 range 128 .. 191;
      Extra_Argument at 0 range 192 .. 255;
   end record;
   for SMP_Core'Size use 256;
   type SMP_Cores is array (Natural range <>) of SMP_Core;
   type SMP_Tag (Count : Natural) is record
      TagInfo      : Tag;
      Flags        : Unsigned_64;
      BSP_LAPIC_ID : Unsigned_32;
      Unused       : Unsigned_32;
      Entries      : SMP_Cores (1 .. Count);
   end record;
   for SMP_Tag use record
      TagInfo      at 0 range   0 .. 127;
      Flags        at 0 range 128 .. 191;
      BSP_LAPIC_ID at 0 range 192 .. 223;
      Unused       at 0 range 224 .. 255;
      Count        at 0 range 256 .. 319;
   end record;

   Stivale_Tag : access Header;

   --  Find a header.
   function Get_Tag
      (Proto     : access Header;
      Identifier : Unsigned_64) return Virtual_Address;
end Arch.Stivale2;
